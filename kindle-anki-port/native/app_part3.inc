static void stop_audio(App *app) {
    if (app->audio_pid > 0) {
        kill(app->audio_pid, SIGTERM);
        (void)waitpid(app->audio_pid, NULL, 0);
        app->audio_pid = 0;
    }
}

static int safe_media_name(const char *name) {
    const unsigned char *cursor = (const unsigned char *)name;
    if (!name || !*name || name[0] == '/' || strstr(name, "..") || strchr(name, '\\')) return 0;
    while (*cursor) {
        if (*cursor < 0x20 || *cursor == 0x7f) return 0;
        cursor += 1;
    }
    return 1;
}

static int is_remote_audio_source(const char *source) {
    return source &&
           (strncmp(source, "https://", 8) == 0 || strncmp(source, "http://", 7) == 0);
}

static void play_audio(App *app, const char *source) {
    char resolved[2048];
    const char *target = NULL;
    pid_t child;
    if (is_remote_audio_source(source)) {
        target = source;
    } else {
        if (!safe_media_name(source)) {
            log_line(app, "audio rejected unsafe source");
            return;
        }
        if (snprintf(resolved, sizeof(resolved), "%s/%s", MEDIA_PATH, source) >=
            (int)sizeof(resolved)) {
            log_line(app, "audio path too long");
            return;
        }
        target = resolved;
    }
    stop_audio(app);
    child = fork();
    if (child == 0) {
        execl(AUDIO_BIN, AUDIO_BIN, "--play", target, (char *)NULL);
        _exit(127);
    }
    if (child > 0) app->audio_pid = child;
    else log_line(app, "fork audio failed: %s", strerror(errno));
}

static void play_tts(App *app, const char *text, const char *lang, const char *speed) {
    pid_t child;
    if (!text || !*text) return;
    stop_audio(app);
    child = fork();
    if (child == 0) {
        setenv("ESPEAK_DATA_PATH", TTS_DATA, 1);
        execl(AUDIO_BIN, AUDIO_BIN, "--tts", TTS_BIN, text, lang ? lang : "en",
              speed ? speed : "1", (char *)NULL);
        _exit(127);
    }
    if (child > 0) app->audio_pid = child;
    else log_line(app, "fork tts failed: %s", strerror(errno));
}

static void set_controls(App *app, const char *mode, const char *uri) {
    int index;
    int reviewer = app->view == VIEW_REVIEWER;
    if (!mode) mode = "none";
    if (reviewer) {
        app->ui.gtk_widget_show(app->back_button);
        app->ui.gtk_widget_show(app->page_up_button);
        app->ui.gtk_widget_show(app->page_down_button);
    } else {
        app->ui.gtk_widget_hide(app->back_button);
        app->ui.gtk_widget_hide(app->page_up_button);
        app->ui.gtk_widget_hide(app->page_down_button);
    }
    if (reviewer && strcmp(mode, "question") == 0) {
        app->ui.gtk_widget_show(app->show_answer_button);
        app->ui.gtk_widget_show(app->bury_button);
        for (index = 0; index < 4; index += 1) app->ui.gtk_widget_hide(app->rating_buttons[index]);
    } else if (reviewer && strcmp(mode, "answer") == 0) {
        static const char *keys[4] = {"again", "hard", "good", "easy"};
        static const char *names[4] = {"Again", "Hard", "Good", "Easy"};
        app->ui.gtk_widget_hide(app->show_answer_button);
        app->ui.gtk_widget_show(app->bury_button);
        for (index = 0; index < 4; index += 1) {
            char *interval = query_value(uri, keys[index]);
            char label[96];
            snprintf(label, sizeof(label), "%s%s%s", names[index],
                     interval && *interval ? "\n" : "", interval ? interval : "");
            app->ui.gtk_button_set_label(app->rating_buttons[index], label);
            app->ui.gtk_widget_show(app->rating_buttons[index]);
            free(interval);
        }
    } else {
        app->ui.gtk_widget_hide(app->show_answer_button);
        app->ui.gtk_widget_hide(app->bury_button);
        for (index = 0; index < 4; index += 1) app->ui.gtk_widget_hide(app->rating_buttons[index]);
    }
}

static void load_decks(App *app) {
    stop_audio(app);
    app->view = VIEW_DECKS;
    set_controls(app, "none", "");
    app->ui.webkit_web_view_load_html_string(app->web_view, app->deck_html,
                                              "file:///mnt/us/extensions/kindle-anki-port/web/");
}

static int valid_pixel_density(float density) {
    /* Reject NaN, infinities and values outside a defensive Kindle range. */
    return density == density && density >= 0.75f && density <= 4.50f;
}

static void prepare_webkit_global(App *app) {
    /* Mesquite enables W3C CSS pixels before creating its first WebView. */
    if (app->ui.webkit_web_view_set_use_w3c_css_pixels) {
        app->ui.webkit_web_view_set_use_w3c_css_pixels(TRUE_VALUE);
    }
}

static void configure_webview(App *app) {
    float density = 1.0f;
    int native_density = 0;
    int requires_scaling;

    if (app->ui.webkit_web_view_set_use_w3c_css_pixels) {
        app->ui.webkit_web_view_set_use_w3c_css_pixels(TRUE_VALUE);
    }
    if (app->ui.webkit_web_view_get_pixel_density) {
        density = app->ui.webkit_web_view_get_pixel_density();
        if (valid_pixel_density(density)) native_density = 1;
        else {
            log_line(app, "renderer invalid pixel density=%.4f; falling back to 1.0",
                     (double)density);
            density = 1.0f;
        }
    }

    requires_scaling = density < 0.999f || density > 1.001f;
    if (requires_scaling && !app->ui.webkit_web_view_set_full_content_zoom) {
        /* A density zoom without full-content zoom scales text only on old
         * WebKitGTK and recreates the original RAnki rendering defect. */
        log_line(app,
                 "renderer density=%.4f but full-content zoom is unavailable; using 1.0",
                 (double)density);
        density = 1.0f;
        requires_scaling = 0;
    }
    if (requires_scaling && app->ui.webkit_web_view_set_full_content_zoom) {
        app->ui.webkit_web_view_set_full_content_zoom(app->web_view, TRUE_VALUE);
    }
    if (app->ui.webkit_web_view_set_zoom_level) {
        app->ui.webkit_web_view_set_zoom_level(app->web_view, density);
    }
    log_line(app,
             "renderer css_pixels=%d native_density=%d full_content_zoom=%d density=%.4f",
             app->ui.webkit_web_view_set_use_w3c_css_pixels != NULL,
             native_density,
             requires_scaling && app->ui.webkit_web_view_set_full_content_zoom != NULL,
             (double)density);
}

static void load_reviewer(App *app) {
    app->view = VIEW_REVIEWER;
    set_controls(app, "none", "");
    app->ui.webkit_web_view_load_html_string(app->web_view, app->review_html,
                                              "file:///mnt/us/extensions/kindle-anki-port/web/");
}

static void send_deck_tree(App *app) {
    if (!app->core || !app->collection_open) {
        send_local_error(app, "kapDecks", "deck_tree",
                         app->startup_error ? app->startup_error : "collection is not open");
        return;
    }
    send_json(app, "kapDecks", "deck_tree", app->core_api.deck_tree(app->core));
}

static void send_next_question(App *app) {
    if (!app->core || !app->collection_open) {
        send_local_error(app, "kapReviewer", "next_question", "collection is not open");
        return;
    }
    send_json(app, "kapReviewer", "next_question", app->core_api.next_question(app->core));
}

static void dispatch_uri(App *app, const char *uri) {
    const char *prefix = "kap://v1/";
    const char *start;
    const char *query;
    char operation[128];
    size_t length;
    if (strncmp(uri, prefix, strlen(prefix)) != 0) return;
    start = uri + strlen(prefix);
    query = strchr(start, '?');
    length = query ? (size_t)(query - start) : strlen(start);
    if (length >= sizeof(operation)) length = sizeof(operation) - 1;
    memcpy(operation, start, length);
    operation[length] = '\0';
    log_line(app, "operation=%s", operation);

    if (strcmp(operation, "ready") == 0) {
        char *view = query_value(uri, "view");
        if (view && strcmp(view, "decks") == 0) send_deck_tree(app);
        else if (view && strcmp(view, "reviewer") == 0) send_next_question(app);
        free(view);
    } else if (strcmp(operation, "deck/select") == 0) {
        char *id = query_value(uri, "id");
        if (id) {
            char *reply = app->core_api.set_current_deck(app->core, strtoll(id, NULL, 10));
            if (reply && strstr(reply, "\"ok\":true")) {
                app->core_api.string_free(reply);
                load_reviewer(app);
            } else if (reply) {
                send_json(app, "kapDecks", "set_current_deck", reply);
            }
        }
        free(id);
    } else if (strcmp(operation, "deck/collapse") == 0) {
        char *id = query_value(uri, "id");
        char *collapsed = query_value(uri, "collapsed");
        if (id && collapsed) {
            char *reply = app->core_api.set_deck_collapsed(
                app->core, strtoll(id, NULL, 10), (uint8_t)(atoi(collapsed) != 0));
            if (reply) app->core_api.string_free(reply);
            send_deck_tree(app);
        }
        free(id);
        free(collapsed);
    } else if (strcmp(operation, "review/next") == 0) {
        send_next_question(app);
    } else if (strcmp(operation, "review/reveal") == 0) {
        char *typed = query_value(uri, "typed");
        send_json(app, "kapReviewer", "reveal_answer",
                  app->core_api.reveal_answer(app->core, typed ? typed : ""));
        free(typed);
    } else if (strcmp(operation, "review/rate") == 0) {
        char *rating = query_value(uri, "rating");
        char *milliseconds = query_value(uri, "elapsed_ms");
        send_json(app, "kapReviewer", "answer",
                  app->core_api.answer(app->core,
                                       rating ? (uint32_t)strtoul(rating, NULL, 10) : 0,
                                       milliseconds ? (uint32_t)strtoul(milliseconds, NULL, 10) : 0));
        free(rating);
        free(milliseconds);
    } else if (strcmp(operation, "review/bury") == 0) {
        send_json(app, "kapReviewer", "bury", app->core_api.bury(app->core));
    } else if (strcmp(operation, "ui/state") == 0) {
        char *mode = query_value(uri, "mode");
        set_controls(app, mode, uri);
        free(mode);
    } else if (strcmp(operation, "ui/render-failed") == 0) {
        char *message = query_value(uri, "message");
        log_line(app, "renderer failure: %s", message ? message : "unknown");
        free(message);
    } else if (strcmp(operation, "audio/play") == 0) {
        char *source = query_value(uri, "source");
        if (source) play_audio(app, source);
        free(source);
    } else if (strcmp(operation, "audio/tts") == 0) {
        char *text = query_value(uri, "text");
        char *lang = query_value(uri, "lang");
        char *speed = query_value(uri, "speed");
        if (text) play_tts(app, text, lang, speed);
        free(text); free(lang); free(speed);
    } else if (strcmp(operation, "audio/stop") == 0) {
        stop_audio(app);
    } else if (strcmp(operation, "app/back") == 0) {
        load_decks(app);
    } else if (strcmp(operation, "app/close") == 0) {
        app->ui.gtk_main_quit();
    }
}
