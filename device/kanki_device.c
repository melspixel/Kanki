#define _POSIX_C_SOURCE 200809L

#include <ctype.h>
#include <dlfcn.h>
#include <errno.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include "kanki_bridge.h"

#define KANKI_DIR "/mnt/us/extensions/kanki"
#define DATA_DIR "/mnt/us/anki_data"
#define WEBKIT_LIBRARY "/usr/lib/libwebkitgtk-1.0.so.0"
#define GTK_LIBRARY "/usr/lib/libgtk-x11-2.0.so.0"
#define GOBJECT_LIBRARY "/usr/lib/libgobject-2.0.so.0"
#define DEFAULT_BACKEND KANKI_DIR "/libanki-kanki.so"
#define DEFAULT_COLLECTION DATA_DIR "/collection.anki2"
#define DEFAULT_MEDIA DATA_DIR "/collection.media"
#define DEFAULT_MEDIA_DB DATA_DIR "/media.db2"
#define DECK_PAGE KANKI_DIR "/assets/device/decks.html"
#define REVIEWER_PAGE KANKI_DIR "/assets/device/reviewer-shell.html"
#define SYNC_PAGE KANKI_DIR "/assets/device/sync.html"
#define LOG_PATH KANKI_DIR "/kanki.log"

#ifndef KANKI_BUILD_COMMIT
#define KANKI_BUILD_COMMIT "development"
#endif
#ifndef KANKI_ANKI_COMMIT
#define KANKI_ANKI_COMMIT "e5a6fbe27fdd4d57d5f712191b4a753032e57853"
#endif

#define GTK_WINDOW_TOPLEVEL 0

typedef int gboolean;
typedef unsigned long gulong;
typedef void (*GCallback)(void);

typedef struct {
    void (*gtk_init)(int *, char ***);
    void *(*gtk_window_new)(int);
    void (*gtk_window_set_title)(void *, const char *);
    void (*gtk_window_set_default_size)(void *, int, int);
    void (*gtk_window_fullscreen)(void *);
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
    void (*gtk_main)(void);
    void (*gtk_main_quit)(void);

    void *(*webkit_web_view_new)(void);
    void (*webkit_web_view_load_html_string)(void *, const char *, const char *);
    void (*webkit_web_view_execute_script)(void *, const char *);
    const char *(*webkit_network_request_get_uri)(void *);
    void (*webkit_web_policy_decision_ignore)(void *);

    void (*set_w3c_css_pixels)(int);
    float (*get_pixel_density)(void);
    void (*set_full_content_zoom)(void *, gboolean);
    void (*set_zoom_level)(void *, float);

    gulong (*g_signal_connect_data)(void *, const char *, GCallback, void *, GCallback, unsigned int);
} UiApi;

typedef struct {
    void (*string_free)(char *);
    char *(*build_info)(void);
    KankiCore *(*core_new)(char **);
    void (*core_free)(KankiCore *);
    char *(*open_collection)(KankiCore *, const char *, const char *, const char *);
    char *(*close_collection)(KankiCore *);
    char *(*deck_tree)(KankiCore *);
    char *(*set_current_deck)(KankiCore *, int64_t);
    char *(*set_deck_collapsed)(KankiCore *, int64_t, uint8_t);
    char *(*next_card)(KankiCore *);
    char *(*prepare_answer)(KankiCore *, const char *);
    char *(*answer)(KankiCore *, uint32_t, uint32_t);
    char *(*bury_current)(KankiCore *);
    char *(*health)(KankiCore *);
} BackendApi;

typedef enum {
    VIEW_NONE = 0,
    VIEW_DECKS,
    VIEW_REVIEWER,
    VIEW_SYNC
} ViewMode;

typedef struct App App;

typedef struct {
    App *app;
    uint32_t rating;
} RatingContext;

struct App {
    void *gtk_lib;
    void *webkit_lib;
    void *gobject_lib;
    void *backend_lib;
    UiApi ui;
    BackendApi backend;
    KankiCore *core;

    void *window;
    void *web_view;
    void *back_button;
    void *bury_button;
    void *sync_button;
    void *close_button;
    void *show_answer_button;
    void *rating_buttons[4];
    RatingContext rating_contexts[4];

    ViewMode view_mode;
    int collection_open;
    char *startup_error;
    char *deck_html;
    char *reviewer_html;
    char *sync_html;
    int requested_sync;
    int start_sync;
    int have_sync_status;
    int last_sync_status;
    char media_base[512];
    FILE *log;
};

static void log_message(App *app, const char *format, ...) {
    va_list args;
    char timestamp[64];
    time_t now = time(NULL);
    struct tm value;
    localtime_r(&now, &value);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", &value);
    fprintf(app && app->log ? app->log : stderr, "%s ", timestamp);
    va_start(args, format);
    vfprintf(app && app->log ? app->log : stderr, format, args);
    va_end(args);
    fputc('\n', app && app->log ? app->log : stderr);
    fflush(app && app->log ? app->log : stderr);
}

static char *duplicate_string(const char *value) {
    size_t length;
    char *copy;
    if (!value) return NULL;
    length = strlen(value);
    copy = malloc(length + 1);
    if (!copy) return NULL;
    memcpy(copy, value, length + 1);
    return copy;
}

static int load_symbol(void *library, const char *name, void *target, size_t target_size, int required) {
    void *symbol;
    const char *error;
    dlerror();
    symbol = dlsym(library, name);
    error = dlerror();
    if (error || !symbol) {
        if (required) fprintf(stderr, "missing required symbol %s: %s\n", name, error ? error : "not found");
        memset(target, 0, target_size);
        return required ? 0 : 1;
    }
    if (target_size != sizeof(symbol)) {
        if (required) fprintf(stderr, "unsupported function pointer size for %s\n", name);
        memset(target, 0, target_size);
        return required ? 0 : 1;
    }
    memcpy(target, &symbol, sizeof(symbol));
    return 1;
}

#define LOAD_REQUIRED(handle, object, field, name) \
    do { if (!load_symbol((handle), (name), &(object)->field, sizeof((object)->field), 1)) return 0; } while (0)
#define LOAD_OPTIONAL(handle, object, field, name) \
    do { (void)load_symbol((handle), (name), &(object)->field, sizeof((object)->field), 0); } while (0)

static int load_ui(App *app) {
    app->gtk_lib = dlopen(GTK_LIBRARY, RTLD_NOW | RTLD_GLOBAL);
    app->gobject_lib = dlopen(GOBJECT_LIBRARY, RTLD_NOW | RTLD_GLOBAL);
    app->webkit_lib = dlopen(WEBKIT_LIBRARY, RTLD_NOW | RTLD_GLOBAL);
    if (!app->gtk_lib || !app->gobject_lib || !app->webkit_lib) {
        fprintf(stderr, "failed to load Kindle UI libraries: %s\n", dlerror());
        return 0;
    }

    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_init, "gtk_init");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_window_new, "gtk_window_new");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_window_set_title, "gtk_window_set_title");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_window_set_default_size, "gtk_window_set_default_size");
    LOAD_OPTIONAL(app->gtk_lib, &app->ui, gtk_window_fullscreen, "gtk_window_fullscreen");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_vbox_new, "gtk_vbox_new");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_hbox_new, "gtk_hbox_new");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_button_new_with_label, "gtk_button_new_with_label");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_button_set_label, "gtk_button_set_label");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_box_pack_start, "gtk_box_pack_start");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_box_pack_end, "gtk_box_pack_end");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_container_add, "gtk_container_add");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_widget_show_all, "gtk_widget_show_all");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_widget_show, "gtk_widget_show");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_widget_hide, "gtk_widget_hide");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_widget_set_sensitive, "gtk_widget_set_sensitive");
    LOAD_OPTIONAL(app->gtk_lib, &app->ui, gtk_widget_grab_focus, "gtk_widget_grab_focus");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_main, "gtk_main");
    LOAD_REQUIRED(app->gtk_lib, &app->ui, gtk_main_quit, "gtk_main_quit");

    LOAD_REQUIRED(app->webkit_lib, &app->ui, webkit_web_view_new, "webkit_web_view_new");
    LOAD_REQUIRED(app->webkit_lib, &app->ui, webkit_web_view_load_html_string, "webkit_web_view_load_html_string");
    LOAD_REQUIRED(app->webkit_lib, &app->ui, webkit_web_view_execute_script, "webkit_web_view_execute_script");
    LOAD_REQUIRED(app->webkit_lib, &app->ui, webkit_network_request_get_uri, "webkit_network_request_get_uri");
    LOAD_REQUIRED(app->webkit_lib, &app->ui, webkit_web_policy_decision_ignore, "webkit_web_policy_decision_ignore");

    LOAD_OPTIONAL(app->webkit_lib, &app->ui, set_w3c_css_pixels, "webkit_web_view_set_useW3CStd_cssPixelsPerInch");
    LOAD_OPTIONAL(app->webkit_lib, &app->ui, get_pixel_density, "webkit_web_view_get_pixel_density");
    LOAD_OPTIONAL(app->webkit_lib, &app->ui, set_full_content_zoom, "webkit_web_view_set_full_content_zoom");
    LOAD_OPTIONAL(app->webkit_lib, &app->ui, set_zoom_level, "webkit_web_view_set_zoom_level");

    LOAD_REQUIRED(app->gobject_lib, &app->ui, g_signal_connect_data, "g_signal_connect_data");
    return 1;
}

static int load_backend(App *app, const char *path) {
    char *error = NULL;
    char *response;
    app->backend_lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!app->backend_lib) {
        app->startup_error = duplicate_string(dlerror());
        return 0;
    }
    LOAD_REQUIRED(app->backend_lib, &app->backend, string_free, "kanki_string_free");
    LOAD_REQUIRED(app->backend_lib, &app->backend, build_info, "kanki_build_info_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, core_new, "kanki_core_new");
    LOAD_REQUIRED(app->backend_lib, &app->backend, core_free, "kanki_core_free");
    LOAD_REQUIRED(app->backend_lib, &app->backend, open_collection, "kanki_open_collection_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, close_collection, "kanki_close_collection_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, deck_tree, "kanki_deck_tree_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, set_current_deck, "kanki_set_current_deck_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, set_deck_collapsed, "kanki_set_deck_collapsed_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, next_card, "kanki_next_card_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, prepare_answer, "kanki_prepare_answer_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, answer, "kanki_answer_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, bury_current, "kanki_bury_current_json");
    LOAD_REQUIRED(app->backend_lib, &app->backend, health, "kanki_health_json");

    response = app->backend.build_info();
    if (response) {
        log_message(app, "backend_build=%s", response);
        app->backend.string_free(response);
    }
    app->core = app->backend.core_new(&error);
    if (!app->core) {
        app->startup_error = duplicate_string(error ? error : "Anki backend initialization failed");
        if (error) app->backend.string_free(error);
        return 0;
    }
    response = app->backend.open_collection(app->core, DEFAULT_COLLECTION, DEFAULT_MEDIA, DEFAULT_MEDIA_DB);
    if (!response) {
        app->startup_error = duplicate_string("open collection returned NULL");
        return 0;
    }
    log_message(app, "open_collection=%s", response);
    if (!strstr(response, "\"ok\":true")) app->startup_error = duplicate_string(response);
    else app->collection_open = 1;
    app->backend.string_free(response);
    return app->collection_open;
}

static char *read_file(const char *path) {
    FILE *file;
    long length;
    char *buffer;
    size_t read_length;
    file = fopen(path, "rb");
    if (!file) return NULL;
    if (fseek(file, 0, SEEK_END) != 0) { fclose(file); return NULL; }
    length = ftell(file);
    if (length < 0 || fseek(file, 0, SEEK_SET) != 0) { fclose(file); return NULL; }
    buffer = malloc((size_t)length + 1);
    if (!buffer) { fclose(file); return NULL; }
    read_length = fread(buffer, 1, (size_t)length, file);
    fclose(file);
    if (read_length != (size_t)length) { free(buffer); return NULL; }
    buffer[length] = '\0';
    return buffer;
}

static char hex_value(char value) {
    if (value >= '0' && value <= '9') return (char)(value - '0');
    value = (char)tolower((unsigned char)value);
    if (value >= 'a' && value <= 'f') return (char)(value - 'a' + 10);
    return -1;
}

static char *url_decode(const char *value, size_t length) {
    char *output = malloc(length + 1);
    size_t i = 0;
    size_t j = 0;
    if (!output) return NULL;
    while (i < length) {
        if (value[i] == '%' && i + 2 < length) {
            char high = hex_value(value[i + 1]);
            char low = hex_value(value[i + 2]);
            if (high >= 0 && low >= 0) {
                output[j++] = (char)((high << 4) | low);
                i += 3;
                continue;
            }
        }
        output[j++] = value[i] == '+' ? ' ' : value[i];
        i++;
    }
    output[j] = '\0';
    return output;
}

static char *query_value(const char *uri, const char *key) {
    const char *query = strchr(uri, '?');
    size_t key_length = strlen(key);
    if (!query) return NULL;
    query++;
    while (*query) {
        const char *pair_end = strchr(query, '&');
        const char *equals = strchr(query, '=');
        size_t pair_length = pair_end ? (size_t)(pair_end - query) : strlen(query);
        if (equals && equals < query + pair_length && (size_t)(equals - query) == key_length &&
            strncmp(query, key, key_length) == 0) {
            return url_decode(equals + 1, pair_length - (size_t)(equals + 1 - query));
        }
        if (!pair_end) break;
        query = pair_end + 1;
    }
    return NULL;
}

static char *js_escape(const char *value) {
    size_t length = value ? strlen(value) : 0;
    size_t capacity = length * 6 + 1;
    char *output = malloc(capacity);
    size_t i = 0;
    size_t j = 0;
    if (!output) return NULL;
    while (i < length) {
        unsigned char ch = (unsigned char)value[i];
        if (ch == '\\' || ch == '\'') {
            output[j++] = '\\';
            output[j++] = (char)ch;
        } else if (ch == '\n') {
            output[j++] = '\\'; output[j++] = 'n';
        } else if (ch == '\r') {
            output[j++] = '\\'; output[j++] = 'r';
        } else if (ch == '\t') {
            output[j++] = '\\'; output[j++] = 't';
        } else if (ch < 0x20) {
            static const char hex[] = "0123456789abcdef";
            output[j++] = '\\'; output[j++] = 'u'; output[j++] = '0'; output[j++] = '0';
            output[j++] = hex[ch >> 4]; output[j++] = hex[ch & 15];
        } else if (i + 2 < length && ch == 0xE2 && (unsigned char)value[i + 1] == 0x80 &&
                   ((unsigned char)value[i + 2] == 0xA8 || (unsigned char)value[i + 2] == 0xA9)) {
            memcpy(output + j, (unsigned char)value[i + 2] == 0xA8 ? "\\u2028" : "\\u2029", 6);
            j += 6;
            i += 3;
            continue;
        } else {
            output[j++] = (char)ch;
        }
        i++;
    }
    output[j] = '\0';
    return output;
}

static void execute_script(App *app, const char *script) {
    if (app->web_view && script) app->ui.webkit_web_view_execute_script(app->web_view, script);
}

static void send_response(App *app, const char *receiver, const char *command, char *json) {
    char *escaped_command;
    char *escaped_json;
    char *script;
    size_t length;
    if (!json) json = duplicate_string("{\"ok\":false,\"data\":null,\"error\":\"native response was NULL\"}");
    escaped_command = js_escape(command);
    escaped_json = js_escape(json);
    if (!escaped_command || !escaped_json) goto cleanup;
    length = strlen(receiver) * 2 + strlen(escaped_command) + strlen(escaped_json) + 96;
    script = malloc(length);
    if (!script) goto cleanup;
    snprintf(script, length,
             "if(window.%s&&window.%s.nativeResponse){window.%s.nativeResponse('%s','%s');}",
             receiver, receiver, receiver, escaped_command, escaped_json);
    execute_script(app, script);
    free(script);
cleanup:
    free(escaped_command);
    free(escaped_json);
    if (json) app->backend.string_free(json);
}

static void send_local_error(App *app, const char *receiver, const char *command, const char *message) {
    char *escaped = js_escape(message ? message : "unknown error");
    char *json;
    size_t length;
    if (!escaped) return;
    length = strlen(escaped) + 64;
    json = malloc(length);
    if (!json) { free(escaped); return; }
    snprintf(json, length, "{\"ok\":false,\"data\":null,\"error\":\"%s\"}", escaped);
    free(escaped);
    /* This is malloc-owned rather than backend-owned, so deliver directly. */
    {
        char *escaped_command = js_escape(command);
        char *escaped_json = js_escape(json);
        char *script;
        if (escaped_command && escaped_json) {
            size_t script_length = strlen(receiver) * 2 + strlen(escaped_command) + strlen(escaped_json) + 96;
            script = malloc(script_length);
            if (script) {
                snprintf(script, script_length,
                         "if(window.%s&&window.%s.nativeResponse){window.%s.nativeResponse('%s','%s');}",
                         receiver, receiver, receiver, escaped_command, escaped_json);
                execute_script(app, script);
                free(script);
            }
        }
        free(escaped_command);
        free(escaped_json);
    }
    free(json);
}

static void set_review_controls(App *app, const char *mode, const char *uri) {
    int i;
    if (!mode) mode = "none";
    if (strcmp(mode, "question") == 0) {
        app->ui.gtk_widget_show(app->show_answer_button);
        app->ui.gtk_widget_show(app->bury_button);
        for (i = 0; i < 4; i++) app->ui.gtk_widget_hide(app->rating_buttons[i]);
    } else if (strcmp(mode, "answer") == 0) {
        static const char *keys[4] = {"again", "hard", "good", "easy"};
        static const char *names[4] = {"Again", "Hard", "Good", "Easy"};
        app->ui.gtk_widget_hide(app->show_answer_button);
        app->ui.gtk_widget_show(app->bury_button);
        for (i = 0; i < 4; i++) {
            char *interval = query_value(uri, keys[i]);
            char label[96];
            snprintf(label, sizeof(label), "%s%s%s", names[i], interval && *interval ? "\n" : "", interval ? interval : "");
            app->ui.gtk_button_set_label(app->rating_buttons[i], label);
            app->ui.gtk_widget_show(app->rating_buttons[i]);
            free(interval);
        }
    } else {
        app->ui.gtk_widget_hide(app->show_answer_button);
        app->ui.gtk_widget_hide(app->bury_button);
        for (i = 0; i < 4; i++) app->ui.gtk_widget_hide(app->rating_buttons[i]);
    }
}

static void load_decks(App *app) {
    app->view_mode = VIEW_DECKS;
    set_review_controls(app, "none", "");
    app->ui.webkit_web_view_load_html_string(app->web_view, app->deck_html,
                                              "file:///mnt/us/extensions/kanki/assets/device/");
}

static void configure_native_css_pixels(App *app) {
    float density = 1.0f;
    if (app->ui.set_w3c_css_pixels) app->ui.set_w3c_css_pixels(1);
    if (app->ui.get_pixel_density) density = app->ui.get_pixel_density();
    if (!(density >= 0.5f && density <= 4.0f)) density = 1.0f;
    if (app->ui.set_full_content_zoom) app->ui.set_full_content_zoom(app->web_view, 1);
    if (app->ui.set_zoom_level) app->ui.set_zoom_level(app->web_view, density);
    log_message(app, "css_pixels=w3c:%d density_api:%d full_zoom:%d zoom_api:%d density=%.6f",
                app->ui.set_w3c_css_pixels != NULL, app->ui.get_pixel_density != NULL,
                app->ui.set_full_content_zoom != NULL, app->ui.set_zoom_level != NULL, density);
}

static void load_reviewer(App *app) {
    app->view_mode = VIEW_REVIEWER;
    set_review_controls(app, "none", "");
    configure_native_css_pixels(app);
    app->ui.webkit_web_view_load_html_string(app->web_view, app->reviewer_html,
                                              "file:///mnt/us/extensions/kanki/assets/device/");
}

static void load_sync(App *app) {
    app->view_mode = VIEW_SYNC;
    set_review_controls(app, "none", "");
    app->ui.webkit_web_view_load_html_string(app->web_view, app->sync_html,
                                              "file:///mnt/us/extensions/kanki/assets/device/");
}

static void send_deck_tree(App *app) {
    char *response;
    if (!app->core || !app->collection_open) {
        send_local_error(app, "kankiDecks", "deck_tree",
                         app->startup_error ? app->startup_error : "collection is not open");
        return;
    }
    response = app->backend.deck_tree(app->core);
    send_response(app, "kankiDecks", "deck_tree", response);
}

static void send_next_card(App *app) {
    char *response;
    if (!app->core || !app->collection_open) {
        send_local_error(app, "kankiDevice", "next_card", "collection is not open");
        return;
    }
    response = app->backend.next_card(app->core);
    send_response(app, "kankiDevice", "next_card", response);
}

static void dispatch_uri(App *app, const char *uri) {
    const char *prefix = "kanki://";
    const char *command_start;
    const char *query;
    size_t command_length;
    char command[128];
    if (strncmp(uri, prefix, strlen(prefix)) != 0) return;
    command_start = uri + strlen(prefix);
    query = strchr(command_start, '?');
    command_length = query ? (size_t)(query - command_start) : strlen(command_start);
    if (command_length >= sizeof(command)) command_length = sizeof(command) - 1;
    memcpy(command, command_start, command_length);
    command[command_length] = '\0';
    log_message(app, "command=%s", command);

    if (strcmp(command, "ready") == 0) {
        char *view = query_value(uri, "view");
        if (view && strcmp(view, "decks") == 0) send_deck_tree(app);
        else if (view && strcmp(view, "reviewer") == 0) {
            char *base = js_escape(app->media_base);
            if (base) {
                char script[768];
                snprintf(script, sizeof(script),
                         "var b=document.getElementById('kanki-media-base');if(b){b.href='%s';}", base);
                execute_script(app, script);
                free(base);
            }
            send_next_card(app);
        } else if (view && strcmp(view, "sync") == 0 && app->have_sync_status) {
            const char *message;
            char script[512];
            if (app->last_sync_status == 0) message = "Sync completed successfully.";
            else if (app->last_sync_status == 75) message = "A full sync is required. Choose Full Upload or Full Download explicitly.";
            else message = "The previous sync failed. See kanki.log for the redacted diagnostic result.";
            snprintf(script, sizeof(script),
                     "var s=document.getElementById('status');if(s){s.style.display='block';s.textContent='%s';}",
                     message);
            execute_script(app, script);
        }
        free(view);
    } else if (strcmp(command, "deck/select") == 0) {
        char *id = query_value(uri, "id");
        if (id) {
            int64_t deck_id = strtoll(id, NULL, 10);
            char *response = app->backend.set_current_deck(app->core, deck_id);
            if (response && strstr(response, "\"ok\":true")) {
                app->backend.string_free(response);
                load_reviewer(app);
            } else {
                send_response(app, "kankiDecks", "set_current_deck", response);
            }
        }
        free(id);
    } else if (strcmp(command, "deck/collapse") == 0) {
        char *id = query_value(uri, "id");
        char *collapsed = query_value(uri, "collapsed");
        if (id && collapsed) {
            char *response = app->backend.set_deck_collapsed(
                app->core, strtoll(id, NULL, 10), (uint8_t)(atoi(collapsed) != 0));
            if (response) app->backend.string_free(response);
            send_deck_tree(app);
        }
        free(id);
        free(collapsed);
    } else if (strcmp(command, "review/next") == 0) {
        send_next_card(app);
    } else if (strcmp(command, "review/show-answer") == 0) {
        char *typed = query_value(uri, "typed");
        char *response;
        if (!typed) typed = duplicate_string("");
        if (!typed) {
            send_local_error(app, "kankiDevice", "show_answer", "out of memory");
        } else {
            response = app->backend.prepare_answer(app->core, typed);
            send_response(app, "kankiDevice", "show_answer", response);
        }
        free(typed);
    } else if (strcmp(command, "review/answer") == 0) {
        char *rating = query_value(uri, "rating");
        char *milliseconds = query_value(uri, "ms");
        uint32_t rating_value = rating ? (uint32_t)strtoul(rating, NULL, 10) : 0;
        uint32_t ms_value = milliseconds ? (uint32_t)strtoul(milliseconds, NULL, 10) : 0;
        char *response = app->backend.answer(app->core, rating_value, ms_value);
        if (response && strstr(response, "\"ok\":true")) {
            app->backend.string_free(response);
            send_next_card(app);
        } else {
            send_response(app, "kankiDevice", "answer", response);
        }
        free(rating);
        free(milliseconds);
    } else if (strcmp(command, "review/bury") == 0) {
        char *response = app->backend.bury_current(app->core);
        if (response && strstr(response, "\"ok\":true")) {
            app->backend.string_free(response);
            send_next_card(app);
        } else {
            send_response(app, "kankiDevice", "bury", response);
        }
    } else if (strcmp(command, "sync/run") == 0) {
        char *mode = query_value(uri, "mode");
        if (mode && strcmp(mode, "normal") == 0) app->requested_sync = 80;
        else if (mode && strcmp(mode, "upload") == 0) app->requested_sync = 81;
        else if (mode && strcmp(mode, "download") == 0) app->requested_sync = 82;
        else send_local_error(app, "kankiDevice", "sync", "invalid sync mode");
        if (app->requested_sync) app->ui.gtk_main_quit();
        free(mode);
    } else if (strcmp(command, "ui/state") == 0) {
        char *mode = query_value(uri, "mode");
        set_review_controls(app, mode, uri);
        free(mode);
    } else if (strcmp(command, "audio/play") == 0 || strcmp(command, "audio/tts") == 0) {
        send_local_error(app, "kankiDevice", "audio",
                         "audio service is not yet linked in this pre-hardware build");
    } else if (strcmp(command, "app/back") == 0) {
        load_decks(app);
    } else if (strcmp(command, "app/close") == 0) {
        app->ui.gtk_main_quit();
    }
}

static gboolean on_navigation_policy(void *web_view, void *frame, void *request,
                                     void *action, void *decision, void *user_data) {
    App *app = user_data;
    const char *uri;
    (void)web_view;
    (void)frame;
    (void)action;
    uri = app->ui.webkit_network_request_get_uri(request);
    if (uri && strncmp(uri, "kanki://", 8) == 0) {
        app->ui.webkit_web_policy_decision_ignore(decision);
        dispatch_uri(app, uri);
        return 1;
    }
    return 0;
}

static gboolean on_window_delete(void *widget, void *event, void *user_data) {
    App *app = user_data;
    (void)widget;
    (void)event;
    app->ui.gtk_main_quit();
    return 1;
}

static void on_back_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    load_decks(app);
}

static void on_bury_clicked(void *button, void *user_data) {
    App *app = user_data;
    char *response;
    (void)button;
    response = app->backend.bury_current(app->core);
    if (response && strstr(response, "\"ok\":true")) {
        app->backend.string_free(response);
        send_next_card(app);
    } else {
        send_response(app, "kankiDevice", "bury", response);
    }
}

static void on_show_answer_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    execute_script(app, "if(window.kankiDevice){window.kankiDevice.requestShowAnswer();}");
}

static void on_sync_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    load_sync(app);
}

static void on_rating_clicked(void *button, void *user_data) {
    RatingContext *context = user_data;
    App *app = context->app;
    char *response;
    (void)button;
    response = app->backend.answer(app->core, context->rating, 0);
    if (response && strstr(response, "\"ok\":true")) {
        app->backend.string_free(response);
        send_next_card(app);
    } else {
        send_response(app, "kankiDevice", "answer", response);
    }
}

static void on_close_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    app->ui.gtk_main_quit();
}

static void connect_signal(App *app, void *instance, const char *name, GCallback callback, void *data) {
    app->ui.g_signal_connect_data(instance, name, callback, data, NULL, 0);
}

static int build_window(App *app, int *argc, char ***argv) {
    void *root;
    void *top;
    void *bottom;
    int i;
    static const char *rating_names[4] = {"Again", "Hard", "Good", "Easy"};

    app->ui.gtk_init(argc, argv);
    app->window = app->ui.gtk_window_new(GTK_WINDOW_TOPLEVEL);
    root = app->ui.gtk_vbox_new(0, 4);
    top = app->ui.gtk_hbox_new(0, 4);
    bottom = app->ui.gtk_hbox_new(1, 4);
    app->web_view = app->ui.webkit_web_view_new();
    if (!app->window || !root || !top || !bottom || !app->web_view) return 0;

    app->back_button = app->ui.gtk_button_new_with_label("Back");
    app->bury_button = app->ui.gtk_button_new_with_label("Bury");
    app->sync_button = app->ui.gtk_button_new_with_label("Sync");
    app->close_button = app->ui.gtk_button_new_with_label("Close");
    app->show_answer_button = app->ui.gtk_button_new_with_label("Show Answer");
    for (i = 0; i < 4; i++) {
        app->rating_buttons[i] = app->ui.gtk_button_new_with_label(rating_names[i]);
        app->rating_contexts[i].app = app;
        app->rating_contexts[i].rating = (uint32_t)(i + 1);
    }

    app->ui.gtk_window_set_title(app->window, "Kanki");
    app->ui.gtk_window_set_default_size(app->window, 1272, 1696);
    if (app->ui.gtk_window_fullscreen) app->ui.gtk_window_fullscreen(app->window);
    app->ui.gtk_container_add(app->window, root);

    app->ui.gtk_box_pack_start(top, app->back_button, 0, 0, 0);
    app->ui.gtk_box_pack_start(top, app->bury_button, 0, 0, 0);
    app->ui.gtk_box_pack_end(top, app->close_button, 0, 0, 0);
    app->ui.gtk_box_pack_end(top, app->sync_button, 0, 0, 0);
    app->ui.gtk_box_pack_start(root, top, 0, 0, 0);
    app->ui.gtk_box_pack_start(root, app->web_view, 1, 1, 0);
    app->ui.gtk_box_pack_start(bottom, app->show_answer_button, 1, 1, 0);
    for (i = 0; i < 4; i++) app->ui.gtk_box_pack_start(bottom, app->rating_buttons[i], 1, 1, 0);
    app->ui.gtk_box_pack_end(root, bottom, 0, 0, 0);

    connect_signal(app, app->window, "delete-event", (GCallback)on_window_delete, app);
    connect_signal(app, app->web_view, "navigation-policy-decision-requested",
                   (GCallback)on_navigation_policy, app);
    connect_signal(app, app->back_button, "clicked", (GCallback)on_back_clicked, app);
    connect_signal(app, app->bury_button, "clicked", (GCallback)on_bury_clicked, app);
    connect_signal(app, app->sync_button, "clicked", (GCallback)on_sync_clicked, app);
    connect_signal(app, app->show_answer_button, "clicked", (GCallback)on_show_answer_clicked, app);
    connect_signal(app, app->close_button, "clicked", (GCallback)on_close_clicked, app);
    for (i = 0; i < 4; i++) {
        connect_signal(app, app->rating_buttons[i], "clicked", (GCallback)on_rating_clicked,
                       &app->rating_contexts[i]);
    }
    app->ui.gtk_widget_show_all(app->window);
    set_review_controls(app, "none", "");
    return 1;
}

static void cleanup(App *app) {
    char *response;
    if (!app) return;
    if (app->core && app->collection_open) {
        response = app->backend.close_collection(app->core);
        if (response) {
            log_message(app, "close_collection=%s", response);
            app->backend.string_free(response);
        }
    }
    if (app->core && app->backend.core_free) app->backend.core_free(app->core);
    free(app->startup_error);
    free(app->deck_html);
    free(app->reviewer_html);
    free(app->sync_html);
    if (app->backend_lib) dlclose(app->backend_lib);
    if (app->webkit_lib) dlclose(app->webkit_lib);
    if (app->gobject_lib) dlclose(app->gobject_lib);
    if (app->gtk_lib) dlclose(app->gtk_lib);
    if (app->log && app->log != stderr) fclose(app->log);
}

int main(int argc, char **argv) {
    App app;
    const char *backend_path = DEFAULT_BACKEND;
    int i;
    int exit_status;
    memset(&app, 0, sizeof(app));
    app.log = fopen(LOG_PATH, "a");
    if (!app.log) app.log = stderr;
    snprintf(app.media_base, sizeof(app.media_base), "file://%s/", DEFAULT_MEDIA);
    log_message(&app, "start build=%s anki=%s", KANKI_BUILD_COMMIT, KANKI_ANKI_COMMIT);

    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--backend") == 0 && i + 1 < argc) backend_path = argv[++i];
        else if (strcmp(argv[i], "--start-sync") == 0) app.start_sync = 1;
        else if (strcmp(argv[i], "--sync-status") == 0 && i + 1 < argc) {
            app.last_sync_status = atoi(argv[++i]);
            app.have_sync_status = 1;
        } else {
            fprintf(stderr, "usage: %s [--backend PATH] [--start-sync] [--sync-status CODE]\n", argv[0]);
            cleanup(&app);
            return 64;
        }
    }
    if (!load_ui(&app)) {
        cleanup(&app);
        return 2;
    }
    app.deck_html = read_file(DECK_PAGE);
    app.reviewer_html = read_file(REVIEWER_PAGE);
    app.sync_html = read_file(SYNC_PAGE);
    if (!app.deck_html || !app.reviewer_html || !app.sync_html) {
        log_message(&app, "failed to read UI assets");
        cleanup(&app);
        return 3;
    }
    (void)load_backend(&app, backend_path);
    if (!build_window(&app, &argc, &argv)) {
        log_message(&app, "failed to create GTK window");
        cleanup(&app);
        return 4;
    }
    if (app.start_sync) load_sync(&app);
    else load_decks(&app);
    if (app.ui.gtk_widget_grab_focus) app.ui.gtk_widget_grab_focus(app.web_view);
    app.ui.gtk_main();
    exit_status = app.requested_sync;
    cleanup(&app);
    return exit_status;
}
