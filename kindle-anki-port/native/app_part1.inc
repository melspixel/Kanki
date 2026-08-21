#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

#include "kap_core.h"

#ifndef APP_DIR
#define APP_DIR "/mnt/us/extensions/kindle-anki-port"
#endif
#ifndef DATA_DIR
#define DATA_DIR "/mnt/us/anki_data"
#endif
#define DEFAULT_BACKEND APP_DIR "/libanki-kindle.so"
#define COLLECTION_PATH DATA_DIR "/collection.anki2"
#define MEDIA_PATH DATA_DIR "/collection.media"
#define MEDIA_DB_PATH DATA_DIR "/media.db2"
#define DECK_PAGE APP_DIR "/web/decks.html"
#define REVIEW_PAGE APP_DIR "/web/reviewer.html"
#define AUDIO_BIN APP_DIR "/kap-audio"
#define TTS_BIN APP_DIR "/tts/bin/espeak-ng"
#define TTS_DATA APP_DIR "/tts/share/espeak-ng-data"
#define LOG_PATH APP_DIR "/kindle-anki-port.log"

#ifndef KAP_BUILD_COMMIT
#define KAP_BUILD_COMMIT "development"
#endif
#ifndef KAP_ANKI_COMMIT
#define KAP_ANKI_COMMIT "unknown"
#endif

#define GTK_WINDOW_TOPLEVEL 0
#define TRUE_VALUE 1
#define FALSE_VALUE 0

typedef int gboolean;
typedef unsigned int guint;
typedef unsigned long gulong;
typedef void (*GCallback)(void);

typedef struct {
    void (*gtk_init)(int *, char ***);
    void *(*gtk_window_new)(int);
    void (*gtk_window_set_title)(void *, const char *);
    void (*gtk_window_set_default_size)(void *, int, int);
    void (*gtk_window_fullscreen)(void *);
    void (*gtk_window_present)(void *);
    void *(*gtk_vbox_new)(gboolean, int);
    void *(*gtk_hbox_new)(gboolean, int);
    void *(*gtk_button_new_with_label)(const char *);
    void (*gtk_button_set_label)(void *, const char *);
    void (*gtk_box_pack_start)(void *, void *, gboolean, gboolean, unsigned int);
    void (*gtk_box_pack_end)(void *, void *, gboolean, gboolean, unsigned int);
    void (*gtk_container_add)(void *, void *);
    void (*gtk_widget_show_all)(void *);
    void (*gtk_widget_show)(void *);
    void (*gtk_widget_hide)(void *);
    void (*gtk_widget_set_sensitive)(void *, gboolean);
    void (*gtk_widget_grab_focus)(void *);
    void (*gtk_widget_destroy)(void *);
    void (*gtk_main)(void);
    void (*gtk_main_quit)(void);

    void *(*webkit_web_view_new)(void);
    void (*webkit_web_view_load_html_string)(void *, const char *, const char *);
    void (*webkit_web_view_execute_script)(void *, const char *);
    const char *(*webkit_network_request_get_uri)(void *);
    void (*webkit_web_policy_decision_ignore)(void *);
    void (*webkit_web_view_set_full_content_zoom)(void *, gboolean);
    void (*webkit_web_view_set_zoom_level)(void *, float);
    void (*webkit_web_view_set_use_w3c_css_pixels)(int);
    float (*webkit_web_view_get_pixel_density)(void);

    gulong (*g_signal_connect_data)(void *, const char *, GCallback, void *, GCallback, unsigned int);
    guint (*g_timeout_add)(guint, gboolean (*)(void *), void *);
} UiApi;

typedef struct {
    void (*string_free)(char *);
    char *(*build_info)(void);
    KapCore *(*core_new)(char **);
    void (*core_free)(KapCore *);
    char *(*open_collection)(KapCore *, const char *, const char *, const char *);
    char *(*close_collection)(KapCore *);
    char *(*deck_tree)(KapCore *);
    char *(*set_current_deck)(KapCore *, int64_t);
    char *(*set_deck_collapsed)(KapCore *, int64_t, uint8_t);
    char *(*next_question)(KapCore *);
    char *(*reveal_answer)(KapCore *, const char *);
    char *(*answer)(KapCore *, uint32_t, uint32_t);
    char *(*bury)(KapCore *);
    char *(*health)(KapCore *);
} CoreApi;

typedef enum {
    VIEW_NONE = 0,
    VIEW_DECKS,
    VIEW_REVIEWER
} View;

typedef struct App App;

typedef struct {
    App *app;
    uint32_t rating;
} RatingContext;

struct App {
    void *gtk_lib;
    void *webkit_lib;
    void *gobject_lib;
    void *glib_lib;
    void *backend_lib;
    UiApi ui;
    CoreApi core_api;
    KapCore *core;
    int collection_open;

    void *window;
    void *web_view;
    void *back_button;
    void *page_up_button;
    void *page_down_button;
    void *bury_button;
    void *sync_button;
    void *close_button;
    void *show_answer_button;
    void *rating_buttons[4];
    RatingContext rating_contexts[4];

    View view;
    char *deck_html;
    char *review_html;
    char *startup_error;
    pid_t audio_pid;
    FILE *log;
};

static volatile sig_atomic_t g_raise_requested = 0;
static volatile sig_atomic_t g_quit_requested = 0;

static void on_signal(int signal_number) {
    if (signal_number == SIGUSR1) g_raise_requested = 1;
    else g_quit_requested = 1;
}

static void log_line(App *app, const char *format, ...) {
    va_list args;
    time_t now = time(NULL);
    struct tm local;
    char stamp[32];
    localtime_r(&now, &local);
    strftime(stamp, sizeof(stamp), "%Y-%m-%d %H:%M:%S", &local);
    fprintf(app && app->log ? app->log : stderr, "%s ", stamp);
    va_start(args, format);
    vfprintf(app && app->log ? app->log : stderr, format, args);
    va_end(args);
    fputc('\n', app && app->log ? app->log : stderr);
    fflush(app && app->log ? app->log : stderr);
}

static char *copy_string(const char *value) {
    size_t size;
    char *copy;
    if (!value) return NULL;
    size = strlen(value) + 1;
    copy = malloc(size);
    if (copy) memcpy(copy, value, size);
    return copy;
}

static char *read_file(const char *path) {
    FILE *file = fopen(path, "rb");
    char *buffer;
    long size;
    size_t read_size;
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0 || (size = ftell(file)) < 0 ||
        fseek(file, 0, SEEK_SET) != 0) {
        fclose(file);
        return NULL;
    }
    buffer = malloc((size_t)size + 1);
    if (!buffer) { fclose(file); return NULL; }
    read_size = fread(buffer, 1, (size_t)size, file);
    fclose(file);
    if (read_size != (size_t)size) { free(buffer); return NULL; }
    buffer[size] = '\0';
    return buffer;
}

static int load_symbol(void *library, const char *name, void *target, size_t size, int required) {
    void *symbol;
    const char *error;
    dlerror();
    symbol = dlsym(library, name);
    error = dlerror();
    if (error || !symbol) {
        memset(target, 0, size);
        if (required) fprintf(stderr, "missing symbol %s: %s\n", name, error ? error : "not found");
        return required ? 0 : 1;
    }
    if (size != sizeof(symbol)) {
        memset(target, 0, size);
        return required ? 0 : 1;
    }
    memcpy(target, &symbol, sizeof(symbol));
    return 1;
}

#define REQUIRE(handle, object, field, symbol) \
    do { if (!load_symbol((handle), (symbol), &(object)->field, sizeof((object)->field), 1)) return 0; } while (0)
#define OPTIONAL(handle, object, field, symbol) \
    do { (void)load_symbol((handle), (symbol), &(object)->field, sizeof((object)->field), 0); } while (0)
