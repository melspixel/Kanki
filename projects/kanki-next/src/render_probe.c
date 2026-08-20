#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kindle_webkit_scale.h"
#include "probe_asset.h"

typedef void GtkWidget;
typedef void *GCallback;
typedef unsigned long GSignalHandlerId;

enum { GTK_WINDOW_TOPLEVEL = 0 };

typedef struct {
    void *gtk;
    void *gobject;
    void *webkit;

    void (*gtk_init)(int *argc, char ***argv);
    GtkWidget *(*gtk_window_new)(int window_type);
    void (*gtk_window_set_title)(void *window, const char *title);
    void (*gtk_window_fullscreen)(void *window);
    GtkWidget *(*gtk_vbox_new)(int homogeneous, int spacing);
    GtkWidget *(*gtk_button_new_with_label)(const char *label);
    void (*gtk_box_pack_start)(void *box, void *child, int expand, int fill, unsigned int padding);
    void (*gtk_container_add)(void *container, void *widget);
    void (*gtk_widget_set_size_request)(void *widget, int width, int height);
    void (*gtk_widget_show_all)(void *widget);
    void (*gtk_widget_destroy)(void *widget);
    void (*gtk_main)(void);
    void (*gtk_main_quit)(void);

    GSignalHandlerId (*g_signal_connect_data)(
        void *instance,
        const char *detailed_signal,
        GCallback handler,
        void *data,
        GCallback destroy_data,
        int connect_flags
    );

    GtkWidget *(*webkit_web_view_new)(void);
    void (*webkit_web_view_load_html_string)(
        void *web_view,
        const char *content,
        const char *base_uri
    );
} RuntimeApi;

typedef struct {
    RuntimeApi *runtime;
    GtkWidget *window;
    FILE *log;
} ProbeState;

static void log_line(FILE *log, const char *key, const char *value)
{
    FILE *out = log != NULL ? log : stderr;
    fprintf(out, "%s=%s\n", key, value != NULL ? value : "");
    fflush(out);
}

static void log_float(FILE *log, const char *key, float value)
{
    FILE *out = log != NULL ? log : stderr;
    fprintf(out, "%s=%.6f\n", key, (double)value);
    fflush(out);
}

static void *open_first(const char *const *names)
{
    size_t index;
    for (index = 0; names[index] != NULL; ++index) {
        void *handle = dlopen(names[index], RTLD_NOW | RTLD_GLOBAL);
        if (handle != NULL) {
            return handle;
        }
    }
    return NULL;
}

static int load_symbol(void *handle, const char *name, void **slot)
{
    *slot = dlsym(handle, name);
    return *slot != NULL;
}

#define LOAD_REQUIRED(handle, api, member) \
    do { \
        if (!load_symbol((handle), #member, (void **)&((api)->member))) { \
            fprintf(stderr, "missing required symbol: %s\n", #member); \
            return 0; \
        } \
    } while (0)

static int runtime_api_load(RuntimeApi *api)
{
    static const char *const gtk_names[] = {
        "libgtk-x11-2.0.so.0", "libgtk-x11-2.0.so", NULL
    };
    static const char *const gobject_names[] = {
        "libgobject-2.0.so.0", "libgobject-2.0.so", NULL
    };
    static const char *const webkit_names[] = {
        "libwebkitgtk-1.0.so.0", "libwebkitgtk-1.0.so", NULL
    };

    memset(api, 0, sizeof(*api));
    api->gtk = open_first(gtk_names);
    api->gobject = open_first(gobject_names);
    api->webkit = open_first(webkit_names);
    if (api->gtk == NULL || api->gobject == NULL || api->webkit == NULL) {
        fprintf(stderr, "unable to load GTK2/GObject/WebKitGTK1 runtime\n");
        return 0;
    }

    LOAD_REQUIRED(api->gtk, api, gtk_init);
    LOAD_REQUIRED(api->gtk, api, gtk_window_new);
    LOAD_REQUIRED(api->gtk, api, gtk_window_set_title);
    LOAD_REQUIRED(api->gtk, api, gtk_window_fullscreen);
    LOAD_REQUIRED(api->gtk, api, gtk_vbox_new);
    LOAD_REQUIRED(api->gtk, api, gtk_button_new_with_label);
    LOAD_REQUIRED(api->gtk, api, gtk_box_pack_start);
    LOAD_REQUIRED(api->gtk, api, gtk_container_add);
    LOAD_REQUIRED(api->gtk, api, gtk_widget_set_size_request);
    LOAD_REQUIRED(api->gtk, api, gtk_widget_show_all);
    LOAD_REQUIRED(api->gtk, api, gtk_widget_destroy);
    LOAD_REQUIRED(api->gtk, api, gtk_main);
    LOAD_REQUIRED(api->gtk, api, gtk_main_quit);
    LOAD_REQUIRED(api->gobject, api, g_signal_connect_data);
    LOAD_REQUIRED(api->webkit, api, webkit_web_view_new);
    LOAD_REQUIRED(api->webkit, api, webkit_web_view_load_html_string);
    return 1;
}

static void on_window_destroy(void *widget, void *user_data)
{
    ProbeState *state = (ProbeState *)user_data;
    (void)widget;
    if (state != NULL && state->runtime != NULL) {
        state->runtime->gtk_main_quit();
    }
}

static void on_exit_clicked(void *button, void *user_data)
{
    ProbeState *state = (ProbeState *)user_data;
    (void)button;
    if (state != NULL && state->runtime != NULL && state->window != NULL) {
        state->runtime->gtk_widget_destroy(state->window);
    }
}

static int on_console_message(
    void *web_view,
    const char *message,
    int line,
    const char *source_id,
    void *user_data
)
{
    ProbeState *state = (ProbeState *)user_data;
    FILE *out = state != NULL && state->log != NULL ? state->log : stderr;
    (void)web_view;
    fprintf(out, "console|line=%d|source=%s|%s\n",
            line,
            source_id != NULL ? source_id : "",
            message != NULL ? message : "");
    fflush(out);
    return 0;
}

static const char *scale_status_name(KankiScaleStatus status)
{
    switch (status) {
    case KANKI_SCALE_NATIVE:
        return "native";
    case KANKI_SCALE_FALLBACK_MISSING_API:
        return "fallback-missing-api";
    case KANKI_SCALE_FALLBACK_INVALID_DENSITY:
        return "fallback-invalid-density";
    case KANKI_SCALE_FATAL_NO_ZOOM_API:
        return "fatal-no-zoom-api";
    default:
        return "unknown";
    }
}

static FILE *open_probe_log(void)
{
    static const char *const paths[] = {
        "/mnt/us/extensions/kanki-next/render-probe.log",
        "/mnt/us/extensions/ranki/kanki-next-render-probe.log",
        "/tmp/kanki-next-render-probe.log",
        NULL
    };
    size_t index;
    for (index = 0; paths[index] != NULL; ++index) {
        FILE *log = fopen(paths[index], "w");
        if (log != NULL) {
            fprintf(log, "KANKI_NEXT_RENDER_PROBE_V1\n");
            fprintf(log, "log_path=%s\n", paths[index]);
            fflush(log);
            return log;
        }
    }
    return NULL;
}

int main(int argc, char **argv)
{
    RuntimeApi runtime;
    KankiWebKitApi webkit_api;
    KankiScaleResult scale;
    ProbeState state;
    GtkWidget *vbox;
    GtkWidget *web_view;
    GtkWidget *exit_button;
    KankiScaleStatus status;

    memset(&state, 0, sizeof(state));
    state.log = open_probe_log();

    if (!runtime_api_load(&runtime)) {
        log_line(state.log, "fatal", "runtime-load-failed");
        return 2;
    }
    state.runtime = &runtime;

    runtime.gtk_init(&argc, &argv);

    kanki_webkit_api_resolve(runtime.webkit, dlsym, &webkit_api);
    log_line(state.log, "has_w3c_css_pixels",
             webkit_api.set_w3c_css_pixels != NULL ? "1" : "0");
    log_line(state.log, "has_pixel_density",
             webkit_api.get_pixel_density != NULL ? "1" : "0");
    log_line(state.log, "has_full_content_zoom",
             webkit_api.set_full_content_zoom != NULL ? "1" : "0");
    log_line(state.log, "has_zoom_level",
             webkit_api.set_zoom_level != NULL ? "1" : "0");
    log_line(state.log, "has_fixed_layout",
             webkit_api.set_fixed_layout != NULL ? "1" : "0");
    log_line(state.log, "prepared_global_css_pixels",
             kanki_webkit_prepare_global_css_pixels(&webkit_api) ? "1" : "0");

    state.window = runtime.gtk_window_new(GTK_WINDOW_TOPLEVEL);
    runtime.gtk_window_set_title(
        state.window,
        "L:A_N:application_ID:kanki.next.probe_O:U_PC:N"
    );
    runtime.gtk_window_fullscreen(state.window);

    vbox = runtime.gtk_vbox_new(0, 0);
    web_view = runtime.webkit_web_view_new();
    exit_button = runtime.gtk_button_new_with_label("Exit renderer probe");
    runtime.gtk_widget_set_size_request(exit_button, -1, 72);

    runtime.gtk_box_pack_start(vbox, web_view, 1, 1, 0);
    runtime.gtk_box_pack_start(vbox, exit_button, 0, 0, 0);
    runtime.gtk_container_add(state.window, vbox);

    runtime.g_signal_connect_data(
        state.window, "destroy", (GCallback)on_window_destroy,
        &state, NULL, 0
    );
    runtime.g_signal_connect_data(
        exit_button, "clicked", (GCallback)on_exit_clicked,
        &state, NULL, 0
    );
    runtime.g_signal_connect_data(
        web_view, "console-message", (GCallback)on_console_message,
        &state, NULL, 0
    );

    status = kanki_webkit_apply_native_scale(web_view, &webkit_api, &scale);
    log_float(state.log, "reported_density", scale.reported_density);
    log_float(state.log, "applied_zoom", scale.applied_zoom);
    fprintf(state.log != NULL ? state.log : stderr,
            "scale_status=%d\nscale_status_name=%s\n",
            (int)status, scale_status_name(status));
    if (state.log != NULL) {
        fflush(state.log);
    }
    if (status == KANKI_SCALE_FATAL_NO_ZOOM_API) {
        log_line(state.log, "fatal", "standard-webkit-zoom-api-missing");
        runtime.gtk_widget_destroy(state.window);
        if (state.log != NULL) {
            fclose(state.log);
        }
        return 3;
    }

    runtime.webkit_web_view_load_html_string(
        web_view,
        KANKI_NEXT_PROBE_HTML,
        "file:///mnt/us/extensions/kanki-next/"
    );
    runtime.gtk_widget_show_all(state.window);
    runtime.gtk_main();

    if (state.log != NULL) {
        fclose(state.log);
    }
    return 0;
}
