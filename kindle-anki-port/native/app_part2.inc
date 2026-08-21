static int load_ui(App *app) {
    app->gtk_lib = dlopen("/usr/lib/libgtk-x11-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    app->gobject_lib = dlopen("/usr/lib/libgobject-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    app->glib_lib = dlopen("/lib/libglib-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!app->glib_lib) app->glib_lib = dlopen("/usr/lib/libglib-2.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    app->webkit_lib = dlopen("/usr/lib/libwebkitgtk-1.0.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (!app->gtk_lib || !app->gobject_lib || !app->glib_lib || !app->webkit_lib) {
        fprintf(stderr, "unable to load Kindle UI libraries: %s\n", dlerror());
        return 0;
    }

    REQUIRE(app->gtk_lib, &app->ui, gtk_init, "gtk_init");
    REQUIRE(app->gtk_lib, &app->ui, gtk_window_new, "gtk_window_new");
    REQUIRE(app->gtk_lib, &app->ui, gtk_window_set_title, "gtk_window_set_title");
    REQUIRE(app->gtk_lib, &app->ui, gtk_window_set_default_size, "gtk_window_set_default_size");
    OPTIONAL(app->gtk_lib, &app->ui, gtk_window_fullscreen, "gtk_window_fullscreen");
    OPTIONAL(app->gtk_lib, &app->ui, gtk_window_present, "gtk_window_present");
    REQUIRE(app->gtk_lib, &app->ui, gtk_vbox_new, "gtk_vbox_new");
    REQUIRE(app->gtk_lib, &app->ui, gtk_hbox_new, "gtk_hbox_new");
    REQUIRE(app->gtk_lib, &app->ui, gtk_button_new_with_label, "gtk_button_new_with_label");
    REQUIRE(app->gtk_lib, &app->ui, gtk_button_set_label, "gtk_button_set_label");
    REQUIRE(app->gtk_lib, &app->ui, gtk_box_pack_start, "gtk_box_pack_start");
    REQUIRE(app->gtk_lib, &app->ui, gtk_box_pack_end, "gtk_box_pack_end");
    REQUIRE(app->gtk_lib, &app->ui, gtk_container_add, "gtk_container_add");
    REQUIRE(app->gtk_lib, &app->ui, gtk_widget_show_all, "gtk_widget_show_all");
    REQUIRE(app->gtk_lib, &app->ui, gtk_widget_show, "gtk_widget_show");
    REQUIRE(app->gtk_lib, &app->ui, gtk_widget_hide, "gtk_widget_hide");
    REQUIRE(app->gtk_lib, &app->ui, gtk_widget_set_sensitive, "gtk_widget_set_sensitive");
    OPTIONAL(app->gtk_lib, &app->ui, gtk_widget_grab_focus, "gtk_widget_grab_focus");
    OPTIONAL(app->gtk_lib, &app->ui, gtk_widget_destroy, "gtk_widget_destroy");
    REQUIRE(app->gtk_lib, &app->ui, gtk_main, "gtk_main");
    REQUIRE(app->gtk_lib, &app->ui, gtk_main_quit, "gtk_main_quit");

    REQUIRE(app->webkit_lib, &app->ui, webkit_web_view_new, "webkit_web_view_new");
    REQUIRE(app->webkit_lib, &app->ui, webkit_web_view_load_html_string, "webkit_web_view_load_html_string");
    REQUIRE(app->webkit_lib, &app->ui, webkit_web_view_execute_script, "webkit_web_view_execute_script");
    REQUIRE(app->webkit_lib, &app->ui, webkit_network_request_get_uri, "webkit_network_request_get_uri");
    REQUIRE(app->webkit_lib, &app->ui, webkit_web_policy_decision_ignore, "webkit_web_policy_decision_ignore");
    OPTIONAL(app->webkit_lib, &app->ui, webkit_web_view_set_full_content_zoom, "webkit_web_view_set_full_content_zoom");
    OPTIONAL(app->webkit_lib, &app->ui, webkit_web_view_set_zoom_level, "webkit_web_view_set_zoom_level");
    OPTIONAL(app->webkit_lib, &app->ui, webkit_web_view_set_use_w3c_css_pixels,
             "webkit_web_view_set_useW3CStd_cssPixelsPerInch");
    OPTIONAL(app->webkit_lib, &app->ui, webkit_web_view_get_pixel_density,
             "webkit_web_view_get_pixel_density");

    REQUIRE(app->gobject_lib, &app->ui, g_signal_connect_data, "g_signal_connect_data");
    REQUIRE(app->glib_lib, &app->ui, g_timeout_add, "g_timeout_add");
    return 1;
}

static int load_core(App *app, const char *path) {
    char *error = NULL;
    char *reply;
    app->backend_lib = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    if (!app->backend_lib) {
        app->startup_error = copy_string(dlerror());
        return 0;
    }
    REQUIRE(app->backend_lib, &app->core_api, string_free, "kap_string_free");
    REQUIRE(app->backend_lib, &app->core_api, build_info, "kap_build_info_json");
    REQUIRE(app->backend_lib, &app->core_api, core_new, "kap_core_new");
    REQUIRE(app->backend_lib, &app->core_api, core_free, "kap_core_free");
    REQUIRE(app->backend_lib, &app->core_api, open_collection, "kap_open_collection_json");
    REQUIRE(app->backend_lib, &app->core_api, close_collection, "kap_close_collection_json");
    REQUIRE(app->backend_lib, &app->core_api, deck_tree, "kap_deck_tree_json");
    REQUIRE(app->backend_lib, &app->core_api, set_current_deck, "kap_set_current_deck_json");
    REQUIRE(app->backend_lib, &app->core_api, set_deck_collapsed, "kap_set_deck_collapsed_json");
    REQUIRE(app->backend_lib, &app->core_api, next_question, "kap_next_question_json");
    REQUIRE(app->backend_lib, &app->core_api, reveal_answer, "kap_reveal_answer_json");
    REQUIRE(app->backend_lib, &app->core_api, answer, "kap_answer_json");
    REQUIRE(app->backend_lib, &app->core_api, bury, "kap_bury_current_json");
    REQUIRE(app->backend_lib, &app->core_api, health, "kap_health_json");

    reply = app->core_api.build_info();
    if (reply) {
        log_line(app, "core=%s", reply);
        app->core_api.string_free(reply);
    }
    app->core = app->core_api.core_new(&error);
    if (!app->core) {
        app->startup_error = copy_string(error ? error : "core initialization failed");
        if (error) app->core_api.string_free(error);
        return 0;
    }
    reply = app->core_api.open_collection(app->core, COLLECTION_PATH, MEDIA_PATH, MEDIA_DB_PATH);
    if (!reply) {
        app->startup_error = copy_string("open collection returned NULL");
        return 0;
    }
    log_line(app, "open_collection=%s", reply);
    app->collection_open = strstr(reply, "\"ok\":true") != NULL;
    if (!app->collection_open) app->startup_error = copy_string(reply);
    app->core_api.string_free(reply);
    return app->collection_open;
}

static int hex_digit(char value) {
    if (value >= '0' && value <= '9') return value - '0';
    value = (char)tolower((unsigned char)value);
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    return -1;
}

static char *url_decode(const char *value, size_t length) {
    char *output = malloc(length + 1);
    size_t source = 0;
    size_t target = 0;
    if (!output) return NULL;
    while (source < length) {
        if (value[source] == '%' && source + 2 < length) {
            int high = hex_digit(value[source + 1]);
            int low = hex_digit(value[source + 2]);
            if (high >= 0 && low >= 0) {
                output[target++] = (char)((high << 4) | low);
                source += 3;
                continue;
            }
        }
        output[target++] = value[source] == '+' ? ' ' : value[source];
        source += 1;
    }
    output[target] = '\0';
    return output;
}

static char *query_value(const char *uri, const char *key) {
    const char *query = strchr(uri, '?');
    size_t key_length = strlen(key);
    if (!query) return NULL;
    query += 1;
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
    char *output = malloc(length * 6 + 1);
    size_t source = 0;
    size_t target = 0;
    if (!output) return NULL;
    while (source < length) {
        unsigned char ch = (unsigned char)value[source];
        if (ch == '\\' || ch == '\'') {
            output[target++] = '\\';
            output[target++] = (char)ch;
        } else if (ch == '\n') {
            output[target++] = '\\'; output[target++] = 'n';
        } else if (ch == '\r') {
            output[target++] = '\\'; output[target++] = 'r';
        } else if (ch == '\t') {
            output[target++] = '\\'; output[target++] = 't';
        } else if (ch < 0x20) {
            static const char hex[] = "0123456789abcdef";
            output[target++] = '\\'; output[target++] = 'u'; output[target++] = '0'; output[target++] = '0';
            output[target++] = hex[ch >> 4]; output[target++] = hex[ch & 15];
        } else if (source + 2 < length && ch == 0xE2 &&
                   (unsigned char)value[source + 1] == 0x80 &&
                   ((unsigned char)value[source + 2] == 0xA8 ||
                    (unsigned char)value[source + 2] == 0xA9)) {
            memcpy(output + target,
                   (unsigned char)value[source + 2] == 0xA8 ? "\\u2028" : "\\u2029", 6);
            target += 6;
            source += 3;
            continue;
        } else {
            output[target++] = (char)ch;
        }
        source += 1;
    }
    output[target] = '\0';
    return output;
}

static void execute_script(App *app, const char *script) {
    if (app->web_view && script) app->ui.webkit_web_view_execute_script(app->web_view, script);
}

static void send_json(App *app, const char *receiver, const char *operation, char *json) {
    char *escaped_operation;
    char *escaped_json;
    char *script;
    size_t size;
    if (!json) return;
    escaped_operation = js_escape(operation);
    escaped_json = js_escape(json);
    if (!escaped_operation || !escaped_json) goto done;
    size = strlen(receiver) * 2 + strlen(escaped_operation) + strlen(escaped_json) + 128;
    script = malloc(size);
    if (!script) goto done;
    snprintf(script, size,
             "if(window.%s&&window.%s.nativeResponse){window.%s.nativeResponse('%s','%s');}",
             receiver, receiver, receiver, escaped_operation, escaped_json);
    execute_script(app, script);
    free(script);
done:
    free(escaped_operation);
    free(escaped_json);
    app->core_api.string_free(json);
}

static void send_local_error(App *app, const char *receiver, const char *operation, const char *message) {
    char *escaped_message = js_escape(message ? message : "unknown error");
    char *json;
    char *escaped_operation;
    char *escaped_json;
    char *script;
    size_t size;
    if (!escaped_message) return;
    size = strlen(escaped_message) + 64;
    json = malloc(size);
    if (!json) { free(escaped_message); return; }
    snprintf(json, size, "{\"ok\":false,\"data\":null,\"error\":\"%s\"}", escaped_message);
    free(escaped_message);
    escaped_operation = js_escape(operation);
    escaped_json = js_escape(json);
    if (escaped_operation && escaped_json) {
        size = strlen(receiver) * 2 + strlen(escaped_operation) + strlen(escaped_json) + 128;
        script = malloc(size);
        if (script) {
            snprintf(script, size,
                     "if(window.%s&&window.%s.nativeResponse){window.%s.nativeResponse('%s','%s');}",
                     receiver, receiver, receiver, escaped_operation, escaped_json);
            execute_script(app, script);
            free(script);
        }
    }
    free(escaped_operation);
    free(escaped_json);
    free(json);
}
