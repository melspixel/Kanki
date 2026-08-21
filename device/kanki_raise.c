#define _POSIX_C_SOURCE 200809L

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define X11_LIBRARY "libX11.so.6"
#define X11_LIBRARY_FALLBACK "/usr/lib/libX11.so.6"
#define KANKI_WINDOW_TITLE "Kanki"
#define REVERT_TO_PARENT 2
#define CURRENT_TIME 0UL

typedef struct _XDisplay Display;
typedef unsigned long Window;
typedef int Status;

typedef struct {
    Display *(*open_display)(const char *);
    int (*close_display)(Display *);
    Window (*default_root_window)(Display *);
    Status (*query_tree)(Display *, Window, Window *, Window *, Window **, unsigned int *);
    Status (*fetch_name)(Display *, Window, char **);
    int (*free_value)(void *);
    int (*map_raised)(Display *, Window);
    int (*set_input_focus)(Display *, Window, int, unsigned long);
    int (*flush)(Display *);
} X11Api;

static int load_symbol(void *library, const char *name, void *target, size_t target_size) {
    void *symbol;
    const char *error;
    dlerror();
    symbol = dlsym(library, name);
    error = dlerror();
    if (error || !symbol || target_size != sizeof(symbol)) {
        fprintf(stderr, "kanki-raise: missing %s: %s\n", name, error ? error : "not found");
        memset(target, 0, target_size);
        return 0;
    }
    memcpy(target, &symbol, sizeof(symbol));
    return 1;
}

#define LOAD(handle, api, field, name) \
    do { if (!load_symbol((handle), (name), &(api)->field, sizeof((api)->field))) return 0; } while (0)

static int load_x11(void *library, X11Api *api) {
    memset(api, 0, sizeof(*api));
    LOAD(library, api, open_display, "XOpenDisplay");
    LOAD(library, api, close_display, "XCloseDisplay");
    LOAD(library, api, default_root_window, "XDefaultRootWindow");
    LOAD(library, api, query_tree, "XQueryTree");
    LOAD(library, api, fetch_name, "XFetchName");
    LOAD(library, api, free_value, "XFree");
    LOAD(library, api, map_raised, "XMapRaised");
    LOAD(library, api, set_input_focus, "XSetInputFocus");
    LOAD(library, api, flush, "XFlush");
    return 1;
}

static Window find_named_window(X11Api *api, Display *display, Window parent, int depth) {
    Window root = 0;
    Window parent_return = 0;
    Window *children = NULL;
    unsigned int count = 0;
    unsigned int i;
    Window found = 0;

    if (depth < 0) return 0;
    if (!api->query_tree(display, parent, &root, &parent_return, &children, &count)) return 0;

    for (i = 0; i < count && !found; i++) {
        char *name = NULL;
        if (api->fetch_name(display, children[i], &name) && name) {
            if (strcmp(name, KANKI_WINDOW_TITLE) == 0) found = children[i];
            api->free_value(name);
        }
        if (!found && depth > 0) found = find_named_window(api, display, children[i], depth - 1);
    }

    if (children) api->free_value(children);
    return found;
}

int main(void) {
    void *library;
    X11Api api;
    Display *display;
    Window root;
    Window target;

    if (!getenv("DISPLAY")) (void)setenv("DISPLAY", ":0", 0);

    library = dlopen(X11_LIBRARY, RTLD_NOW | RTLD_LOCAL);
    if (!library) library = dlopen(X11_LIBRARY_FALLBACK, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "kanki-raise: cannot load X11: %s\n", dlerror());
        return 2;
    }
    if (!load_x11(library, &api)) {
        dlclose(library);
        return 3;
    }

    display = api.open_display(NULL);
    if (!display) {
        fprintf(stderr, "kanki-raise: cannot open X display\n");
        dlclose(library);
        return 4;
    }

    root = api.default_root_window(display);
    target = find_named_window(&api, display, root, 3);
    if (!target) {
        fprintf(stderr, "kanki-raise: Kanki window not found\n");
        api.close_display(display);
        dlclose(library);
        return 5;
    }

    api.map_raised(display, target);
    api.set_input_focus(display, target, REVERT_TO_PARENT, CURRENT_TIME);
    api.flush(display);
    api.close_display(display);
    dlclose(library);
    fprintf(stderr, "kanki-raise: existing Kanki window raised\n");
    return 0;
}
