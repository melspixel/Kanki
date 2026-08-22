static gboolean on_navigation(void *web_view, void *frame, void *request,
                              void *action, void *decision, void *user_data) {
    App *app = user_data;
    const char *uri;
    (void)web_view; (void)frame; (void)action;
    uri = app->ui.webkit_network_request_get_uri(request);
    if (uri && strncmp(uri, "kap://v1/", 9) == 0) {
        app->ui.webkit_web_policy_decision_ignore(decision);
        dispatch_uri(app, uri);
        return TRUE_VALUE;
    }
    return FALSE_VALUE;
}

static gboolean on_window_delete(void *widget, void *event, void *user_data) {
    App *app = user_data;
    (void)widget; (void)event;
    app->ui.gtk_main_quit();
    return TRUE_VALUE;
}

static gboolean lifecycle_tick(void *user_data) {
    App *app = user_data;
    int status;
    if (app->audio_pid > 0) {
        pid_t completed = waitpid(app->audio_pid, &status, WNOHANG);
        if (completed == app->audio_pid || (completed < 0 && errno == ECHILD)) {
            app->audio_pid = 0;
            execute_script(app,
                           "if(window.kapReviewer&&window.kapReviewer.audioFinished){"
                           "window.kapReviewer.audioFinished();}");
        }
    }
    if (g_raise_requested) {
        g_raise_requested = 0;
        if (app->ui.gtk_window_present) app->ui.gtk_window_present(app->window);
        if (app->ui.gtk_window_fullscreen) app->ui.gtk_window_fullscreen(app->window);
        if (app->ui.gtk_widget_grab_focus) app->ui.gtk_widget_grab_focus(app->web_view);
        log_line(app, "existing instance raised");
    }
    if (g_quit_requested) {
        g_quit_requested = 0;
        app->ui.gtk_main_quit();
    }
    return TRUE_VALUE;
}

static void on_back(void *button, void *user_data) {
    (void)button;
    load_decks((App *)user_data);
}

static void on_page_up(void *button, void *user_data) {
    (void)button;
    execute_script((App *)user_data, "if(window.kapReviewer){window.kapReviewer.pageUp();}");
}

static void on_page_down(void *button, void *user_data) {
    (void)button;
    execute_script((App *)user_data, "if(window.kapReviewer){window.kapReviewer.pageDown();}");
}

static void on_bury(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    send_json(app, "kapReviewer", "bury", app->core_api.bury(app->core));
}

static void on_sync(void *button, void *user_data) {
    App *app = user_data;
    FILE *request;
    (void)button;
    request = fopen(APP_DIR "/.sync-request", "w");
    if (request) {
        fputs("sync\n", request);
        fclose(request);
    } else {
        log_line(app, "unable to create sync request: %s", strerror(errno));
    }
    log_line(app, "sync requested; handing off after clean close");
    app->ui.gtk_main_quit();
}

static void on_close(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    app->ui.gtk_main_quit();
}

static void on_show_answer(void *button, void *user_data) {
    (void)button;
    execute_script((App *)user_data,
                   "if(window.kapReviewer){window.kapReviewer.requestReveal();}");
}

static void on_rating(void *button, void *user_data) {
    RatingContext *context = user_data;
    App *app = context->app;
    char script[192];
    (void)button;
    snprintf(script, sizeof(script),
             "if(window.kapBridge){window.kapBridge.send('review/rate',{rating:%u,elapsed_ms:0});}",
             context->rating);
    execute_script(app, script);
}

static void connect_signal(App *app, void *instance, const char *name,
                           GCallback callback, void *data) {
    app->ui.g_signal_connect_data(instance, name, callback, data, NULL, 0);
}

static int build_window(App *app, int *argc, char ***argv) {
    void *root;
    void *top;
    void *bottom;
    int index;
    static const char *rating_names[4] = {"Again", "Hard", "Good", "Easy"};

    app->ui.gtk_init(argc, argv);
    app->window = app->ui.gtk_window_new(GTK_WINDOW_TOPLEVEL);
    root = app->ui.gtk_vbox_new(FALSE_VALUE, 4);
    top = app->ui.gtk_hbox_new(FALSE_VALUE, 4);
    bottom = app->ui.gtk_hbox_new(TRUE_VALUE, 4);
    prepare_webkit_global(app);
    app->web_view = app->ui.webkit_web_view_new();
    if (!app->window || !root || !top || !bottom || !app->web_view) return 0;
    configure_webview(app);

    app->back_button = app->ui.gtk_button_new_with_label("Back");
    app->page_up_button = app->ui.gtk_button_new_with_label("Page Up");
    app->page_down_button = app->ui.gtk_button_new_with_label("Page Down");
    app->bury_button = app->ui.gtk_button_new_with_label("Bury");
    app->sync_button = app->ui.gtk_button_new_with_label("Sync");
    app->close_button = app->ui.gtk_button_new_with_label("Close");
    app->show_answer_button = app->ui.gtk_button_new_with_label("Show Answer");
    for (index = 0; index < 4; index += 1) {
        app->rating_buttons[index] = app->ui.gtk_button_new_with_label(rating_names[index]);
        app->rating_contexts[index].app = app;
        app->rating_contexts[index].rating = (uint32_t)(index + 1);
    }

    app->ui.gtk_window_set_title(app->window, "Kindle Anki Port");
    app->ui.gtk_window_set_default_size(app->window, 1272, 1696);
    if (app->ui.gtk_window_fullscreen) app->ui.gtk_window_fullscreen(app->window);
    app->ui.gtk_container_add(app->window, root);

    app->ui.gtk_box_pack_start(top, app->back_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_start(top, app->page_up_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_start(top, app->page_down_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_start(top, app->bury_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_end(top, app->close_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_end(top, app->sync_button, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_start(root, top, FALSE_VALUE, FALSE_VALUE, 0);
    app->ui.gtk_box_pack_start(root, app->web_view, TRUE_VALUE, TRUE_VALUE, 0);
    app->ui.gtk_box_pack_start(bottom, app->show_answer_button, TRUE_VALUE, TRUE_VALUE, 0);
    for (index = 0; index < 4; index += 1) {
        app->ui.gtk_box_pack_start(bottom, app->rating_buttons[index], TRUE_VALUE, TRUE_VALUE, 0);
    }
    app->ui.gtk_box_pack_end(root, bottom, FALSE_VALUE, FALSE_VALUE, 0);

    connect_signal(app, app->window, "delete-event", (GCallback)on_window_delete, app);
    connect_signal(app, app->web_view, "navigation-policy-decision-requested",
                   (GCallback)on_navigation, app);
    connect_signal(app, app->back_button, "clicked", (GCallback)on_back, app);
    connect_signal(app, app->page_up_button, "clicked", (GCallback)on_page_up, app);
    connect_signal(app, app->page_down_button, "clicked", (GCallback)on_page_down, app);
    connect_signal(app, app->bury_button, "clicked", (GCallback)on_bury, app);
    connect_signal(app, app->sync_button, "clicked", (GCallback)on_sync, app);
    connect_signal(app, app->close_button, "clicked", (GCallback)on_close, app);
    connect_signal(app, app->show_answer_button, "clicked", (GCallback)on_show_answer, app);
    for (index = 0; index < 4; index += 1) {
        connect_signal(app, app->rating_buttons[index], "clicked", (GCallback)on_rating,
                       &app->rating_contexts[index]);
    }

    app->ui.gtk_widget_show_all(app->window);
    set_controls(app, "none", "");
    app->ui.g_timeout_add(250, lifecycle_tick, app);
    return 1;
}

static void cleanup(App *app) {
    char *reply;
    if (!app) return;
    stop_audio(app);
    if (app->core && app->collection_open) {
        reply = app->core_api.close_collection(app->core);
        if (reply) {
            log_line(app, "close_collection=%s", reply);
            app->core_api.string_free(reply);
        }
        app->collection_open = 0;
    }
    if (app->core && app->core_api.core_free) app->core_api.core_free(app->core);
    app->core = NULL;
    if (app->window && app->ui.gtk_widget_destroy) app->ui.gtk_widget_destroy(app->window);
    free(app->deck_html);
    free(app->review_html);
    free(app->startup_error);
    if (app->backend_lib) dlclose(app->backend_lib);
    if (app->webkit_lib) dlclose(app->webkit_lib);
    if (app->glib_lib) dlclose(app->glib_lib);
    if (app->gobject_lib) dlclose(app->gobject_lib);
    if (app->gtk_lib) dlclose(app->gtk_lib);
    if (app->log && app->log != stderr) fclose(app->log);
}

int main(int argc, char **argv) {
    App app;
    const char *backend = DEFAULT_BACKEND;
    struct sigaction action;

    if (argc == 2 && strcmp(argv[1], "--self-test-audio-supervision") == 0) {
        return audio_supervision_self_test();
    }

    memset(&app, 0, sizeof(app));
    app.log = fopen(LOG_PATH, "a");
    if (!app.log) app.log = stderr;
    log_line(&app, "start build=%s anki=%s", KAP_BUILD_COMMIT, KAP_ANKI_COMMIT);

    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGUSR1, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);

    if (argc > 2 && strcmp(argv[1], "--backend") == 0) backend = argv[2];
    if (!load_ui(&app)) { cleanup(&app); return 2; }
    app.deck_html = read_file(DECK_PAGE);
    app.review_html = read_file(REVIEW_PAGE);
    if (!app.deck_html || !app.review_html) {
        log_line(&app, "UI assets are missing");
        cleanup(&app);
        return 3;
    }
    (void)load_core(&app, backend);
    if (!build_window(&app, &argc, &argv)) {
        log_line(&app, "unable to build GTK window");
        cleanup(&app);
        return 4;
    }
    load_decks(&app);
    if (app.ui.gtk_widget_grab_focus) app.ui.gtk_widget_grab_focus(app.web_view);
    app.ui.gtk_main();
    cleanup(&app);
    return 0;
}
