#define KANKI_WINDOW_TITLE "Kanki"
#define X11_LIBRARY "libX11.so.6"
#define X11_LIBRARY_FALLBACK "/usr/lib/libX11.so.6"
#define RTLD_NOW 2
#define RTLD_LOCAL 0
#define REVERT_TO_PARENT 2
#define CURRENT_TIME 0UL

typedef unsigned long k_size_t;
typedef struct _XDisplay Display;
typedef unsigned long Window;
typedef int Status;

extern void *dlopen(const char *, int);
extern void *dlsym(void *, const char *);
extern int dlclose(void *);
#ifndef __arm__
extern long write(int, const void *, unsigned long);
#endif

typedef Display *(*OpenDisplayFn)(const char *);
typedef int (*CloseDisplayFn)(Display *);
typedef Window (*DefaultRootWindowFn)(Display *);
typedef Status (*QueryTreeFn)(Display *, Window, Window *, Window *, Window **, unsigned int *);
typedef Status (*FetchNameFn)(Display *, Window, char **);
typedef int (*FreeFn)(void *);
typedef int (*MapRaisedFn)(Display *, Window);
typedef int (*SetInputFocusFn)(Display *, Window, int, unsigned long);
typedef int (*FlushFn)(Display *);

typedef struct {
    OpenDisplayFn open_display;
    CloseDisplayFn close_display;
    DefaultRootWindowFn default_root_window;
    QueryTreeFn query_tree;
    FetchNameFn fetch_name;
    FreeFn free_value;
    MapRaisedFn map_raised;
    SetInputFocusFn set_input_focus;
    FlushFn flush;
} X11Api;

static k_size_t text_len(const char *text) {
    k_size_t length = 0;
    if (!text) return 0;
    while (text[length]) length++;
    return length;
}

static int text_equal(const char *left, const char *right) {
    if (!left || !right) return 0;
    while (*left && *right && *left == *right) {
        left++;
        right++;
    }
    return *left == *right;
}

static void write_stderr(const char *text) {
#ifdef __arm__
    register unsigned long r0 __asm__("r0") = 2;
    register const char *r1 __asm__("r1") = text;
    register k_size_t r2 __asm__("r2") = text_len(text);
    register unsigned long r7 __asm__("r7") = 4;
    __asm__ volatile("svc 0" : "+r"(r0) : "r"(r1), "r"(r2), "r"(r7) : "memory");
#else
    (void)write(2, text, text_len(text));
#endif
}

#define LOAD_FN(handle, target, name, type) do { \
    union { void *object; type function; } conversion; \
    conversion.object = dlsym((handle), (name)); \
    if (!conversion.object) return 0; \
    (target) = conversion.function; \
} while (0)

static int load_x11(void *library, X11Api *api) {
    LOAD_FN(library, api->open_display, "XOpenDisplay", OpenDisplayFn);
    LOAD_FN(library, api->close_display, "XCloseDisplay", CloseDisplayFn);
    LOAD_FN(library, api->default_root_window, "XDefaultRootWindow", DefaultRootWindowFn);
    LOAD_FN(library, api->query_tree, "XQueryTree", QueryTreeFn);
    LOAD_FN(library, api->fetch_name, "XFetchName", FetchNameFn);
    LOAD_FN(library, api->free_value, "XFree", FreeFn);
    LOAD_FN(library, api->map_raised, "XMapRaised", MapRaisedFn);
    LOAD_FN(library, api->set_input_focus, "XSetInputFocus", SetInputFocusFn);
    LOAD_FN(library, api->flush, "XFlush", FlushFn);
    return 1;
}

static Window find_named_window(X11Api *api, Display *display, Window parent, int depth) {
    Window root = 0;
    Window parent_return = 0;
    Window *children = (Window *)0;
    unsigned int count = 0;
    unsigned int index;
    Window found = 0;

    if (depth < 0) return 0;
    if (!api->query_tree(display, parent, &root, &parent_return, &children, &count)) return 0;

    for (index = 0; index < count && !found; index++) {
        char *name = (char *)0;
        if (api->fetch_name(display, children[index], &name) && name) {
            if (text_equal(name, KANKI_WINDOW_TITLE)) found = children[index];
            api->free_value(name);
        }
        if (!found && depth > 0) {
            found = find_named_window(api, display, children[index], depth - 1);
        }
    }

    if (children) api->free_value(children);
    return found;
}

__attribute__((used, noinline)) int kanki_raise_main(void) {
    void *library;
    X11Api api;
    Display *display;
    Window root;
    Window target;

    library = dlopen(X11_LIBRARY, RTLD_NOW | RTLD_LOCAL);
    if (!library) library = dlopen(X11_LIBRARY_FALLBACK, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        write_stderr("kanki-raise: cannot load X11\n");
        return 2;
    }
    if (!load_x11(library, &api)) {
        write_stderr("kanki-raise: missing X11 symbol\n");
        dlclose(library);
        return 3;
    }

    display = api.open_display((const char *)0);
    if (!display) {
        write_stderr("kanki-raise: cannot open X display\n");
        dlclose(library);
        return 4;
    }

    root = api.default_root_window(display);
    target = find_named_window(&api, display, root, 3);
    if (!target) {
        write_stderr("kanki-raise: Kanki window not found\n");
        api.close_display(display);
        dlclose(library);
        return 5;
    }

    api.map_raised(display, target);
    api.set_input_focus(display, target, REVERT_TO_PARENT, CURRENT_TIME);
    api.flush(display);
    api.close_display(display);
    dlclose(library);
    write_stderr("kanki-raise: existing Kanki window raised\n");
    return 0;
}

#ifdef __arm__
__attribute__((naked, noreturn, visibility("default"))) void _start(void) {
    __asm__ volatile(
        "bl kanki_raise_main\n"
        "mov r7, #1\n"
        "svc #0\n"
        "b .\n"
    );
}
#else
int main(void) {
    return kanki_raise_main();
}
#endif
