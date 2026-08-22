#define main kanki_device_embedded_main
#include "../device/kanki_device.c"
#undef main

static int step_count;
static int web_view_created_step;
static int css_configured_step;
static int first_page_load_step;
static int w3c_calls;
static int density_calls;
static int full_zoom_calls;
static int zoom_level_calls;
static int page_load_calls;
static int widget_token;
static int web_view_token;

static void require_contract(int condition, const char *message) {
    if (condition) return;
    fprintf(stderr, "device CSS lifecycle contract failed: %s\n", message);
    exit(1);
}

static void record_css_step(void) {
    step_count++;
    if (!css_configured_step) css_configured_step = step_count;
}

static void stub_gtk_init(int *argc, char ***argv) {
    (void)argc;
    (void)argv;
}

static void *stub_widget_new(int value) {
    (void)value;
    return &widget_token;
}

static void *stub_box_new(gboolean homogeneous, int spacing) {
    (void)homogeneous;
    (void)spacing;
    return &widget_token;
}

static void *stub_button_new(const char *label) {
    (void)label;
    return &widget_token;
}

static void stub_title(void *window, const char *title) {
    (void)window;
    (void)title;
}

static void stub_default_size(void *window, int width, int height) {
    (void)window;
    (void)width;
    (void)height;
}

static void stub_pack(void *box, void *child, gboolean expand, gboolean fill,
                      unsigned int padding) {
    (void)box;
    (void)child;
    (void)expand;
    (void)fill;
    (void)padding;
}

static void stub_pair(void *parent, void *child) {
    (void)parent;
    (void)child;
}

static void stub_widget(void *widget) {
    (void)widget;
}

static void stub_button_label(void *button, const char *label) {
    (void)button;
    (void)label;
}

static void stub_sensitive(void *widget, gboolean sensitive) {
    (void)widget;
    (void)sensitive;
}

static void *stub_web_view_new(void) {
    step_count++;
    web_view_created_step = step_count;
    return &web_view_token;
}

static void stub_load_html(void *web_view, const char *html, const char *base_uri) {
    step_count++;
    if (!first_page_load_step) first_page_load_step = step_count;
    page_load_calls++;
    require_contract(web_view == &web_view_token, "page load replaced the persistent WebView");
    require_contract(html != NULL, "page load received no document");
    require_contract(base_uri != NULL, "page load received no base URI");
}

static void stub_execute_script(void *web_view, const char *script) {
    (void)web_view;
    (void)script;
}

static void stub_set_w3c_css_pixels(int enabled) {
    record_css_step();
    w3c_calls++;
    require_contract(enabled == 1, "W3C CSS pixels were not enabled");
}

static float stub_get_pixel_density(void) {
    record_css_step();
    density_calls++;
    return 2.0f;
}

static void stub_set_full_content_zoom(void *web_view, gboolean enabled) {
    record_css_step();
    full_zoom_calls++;
    require_contract(web_view == &web_view_token, "full-content zoom targeted another WebView");
    require_contract(enabled == 1, "full-content zoom was not enabled");
}

static void stub_set_zoom_level(void *web_view, float level) {
    record_css_step();
    zoom_level_calls++;
    require_contract(web_view == &web_view_token, "zoom level targeted another WebView");
    require_contract(level == 2.0f, "zoom level did not use the native pixel density");
}

static gulong stub_connect(void *instance, const char *name, GCallback callback,
                           void *data, GCallback destroy_data, unsigned int flags) {
    (void)instance;
    (void)name;
    (void)callback;
    (void)data;
    (void)destroy_data;
    (void)flags;
    return 1;
}

int main(void) {
    App app;
    int argc = 1;
    char *argv_values[] = {(char *)"device-css-lifecycle-contract", NULL};
    char **argv = argv_values;

    memset(&app, 0, sizeof(app));
    app.log = tmpfile();
    if (!app.log) app.log = stderr;
    app.deck_html = (char *)"<html>decks</html>";
    app.reviewer_html = (char *)"<html>reviewer</html>";
    app.sync_html = (char *)"<html>sync</html>";

    app.ui.gtk_init = stub_gtk_init;
    app.ui.gtk_window_new = stub_widget_new;
    app.ui.gtk_window_set_title = stub_title;
    app.ui.gtk_window_set_default_size = stub_default_size;
    app.ui.gtk_vbox_new = stub_box_new;
    app.ui.gtk_hbox_new = stub_box_new;
    app.ui.gtk_button_new_with_label = stub_button_new;
    app.ui.gtk_button_set_label = stub_button_label;
    app.ui.gtk_box_pack_start = stub_pack;
    app.ui.gtk_box_pack_end = stub_pack;
    app.ui.gtk_container_add = stub_pair;
    app.ui.gtk_widget_show_all = stub_widget;
    app.ui.gtk_widget_show = stub_widget;
    app.ui.gtk_widget_hide = stub_widget;
    app.ui.gtk_widget_set_sensitive = stub_sensitive;
    app.ui.webkit_web_view_new = stub_web_view_new;
    app.ui.webkit_web_view_load_html_string = stub_load_html;
    app.ui.webkit_web_view_execute_script = stub_execute_script;
    app.ui.set_w3c_css_pixels = stub_set_w3c_css_pixels;
    app.ui.get_pixel_density = stub_get_pixel_density;
    app.ui.set_full_content_zoom = stub_set_full_content_zoom;
    app.ui.set_zoom_level = stub_set_zoom_level;
    app.ui.g_signal_connect_data = stub_connect;

    require_contract(build_window(&app, &argc, &argv), "window construction failed");
    require_contract(app.web_view == &web_view_token, "persistent WebView identity drifted");
    require_contract(w3c_calls == 1, "CSS pixel policy was not configured once at WebView creation");
    require_contract(density_calls == 1, "pixel density was not read once at WebView creation");
    require_contract(full_zoom_calls == 1, "full-content zoom was not configured once");
    require_contract(zoom_level_calls == 1, "native zoom level was not configured once");
    require_contract(web_view_created_step < css_configured_step,
                     "CSS pixel policy ran before the persistent WebView existed");
    require_contract(page_load_calls == 0, "window construction loaded a page unexpectedly");

    load_decks(&app);
    load_reviewer(&app);
    load_sync(&app);
    load_reviewer(&app);

    require_contract(page_load_calls == 4, "deck/reviewer/sync documents did not share one loader");
    require_contract(css_configured_step < first_page_load_step,
                     "a page loaded before the WebView CSS pixel policy was configured");
    require_contract(w3c_calls == 1 && density_calls == 1 && full_zoom_calls == 1 &&
                         zoom_level_calls == 1,
                     "a view transition reconfigured the persistent WebView");

    if (app.log != stderr) fclose(app.log);
    puts("device CSS lifecycle contract: pass");
    return 0;
}
