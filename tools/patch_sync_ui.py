#!/usr/bin/env python3
"""One-shot migration that wires explicit sync choices into kanki-device."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PATH = ROOT / "device/kanki_device.c"
text = PATH.read_text()


def once(old: str, new: str, label: str) -> None:
    global text
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"{label}: expected source contract not found")
    text = text.replace(old, new, 1)


once(
    '#define REVIEWER_PAGE KANKI_DIR "/assets/device/reviewer-shell.html"\n#define LOG_PATH',
    '#define REVIEWER_PAGE KANKI_DIR "/assets/device/reviewer-shell.html"\n'
    '#define SYNC_PAGE KANKI_DIR "/assets/device/sync.html"\n#define LOG_PATH',
    "sync page constant",
)

once(
    '    VIEW_NONE = 0,\n    VIEW_DECKS,\n    VIEW_REVIEWER\n} ViewMode;',
    '    VIEW_NONE = 0,\n    VIEW_DECKS,\n    VIEW_REVIEWER,\n    VIEW_SYNC\n} ViewMode;',
    "sync view mode",
)

once(
    '    char *deck_html;\n    char *reviewer_html;\n    char media_base[512];',
    '    char *deck_html;\n    char *reviewer_html;\n    char *sync_html;\n'
    '    int requested_sync;\n    int start_sync;\n    int have_sync_status;\n    int last_sync_status;\n'
    '    char media_base[512];',
    "sync app state",
)

once(
    '''static void load_reviewer(App *app) {
    app->view_mode = VIEW_REVIEWER;
    set_review_controls(app, "none", "");
    configure_native_css_pixels(app);
    app->ui.webkit_web_view_load_html_string(app->web_view, app->reviewer_html,
                                              "file:///mnt/us/extensions/kanki/assets/device/");
}
''',
    '''static void load_reviewer(App *app) {
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
''',
    "sync page loader",
)

once(
    '''        else if (view && strcmp(view, "reviewer") == 0) {
            char *base = js_escape(app->media_base);
            if (base) {
                char script[768];
                snprintf(script, sizeof(script),
                         "var b=document.getElementById('kanki-media-base');if(b){b.href='%s';}", base);
                execute_script(app, script);
                free(base);
            }
            send_next_card(app);
        }
        free(view);
''',
    '''        else if (view && strcmp(view, "reviewer") == 0) {
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
''',
    "sync ready status",
)

once(
    '''    } else if (strcmp(command, "review/bury") == 0) {
        char *response = app->backend.bury_current(app->core);
        if (response && strstr(response, "\\\"ok\\\":true")) {
            app->backend.string_free(response);
            send_next_card(app);
        } else {
            send_response(app, "kankiDevice", "bury", response);
        }
    } else if (strcmp(command, "ui/state") == 0) {
''',
    '''    } else if (strcmp(command, "review/bury") == 0) {
        char *response = app->backend.bury_current(app->core);
        if (response && strstr(response, "\\\"ok\\\":true")) {
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
''',
    "sync URI dispatch",
)

once(
    '''static void on_show_answer_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    execute_script(app, "if(window.kankiDevice){window.kankiDevice.requestShowAnswer();}");
}
''',
    '''static void on_show_answer_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    execute_script(app, "if(window.kankiDevice){window.kankiDevice.requestShowAnswer();}");
}

static void on_sync_clicked(void *button, void *user_data) {
    App *app = user_data;
    (void)button;
    load_sync(app);
}
''',
    "sync button callback",
)

once(
    '''    connect_signal(app, app->bury_button, "clicked", (GCallback)on_bury_clicked, app);
    connect_signal(app, app->show_answer_button, "clicked", (GCallback)on_show_answer_clicked, app);
    connect_signal(app, app->close_button, "clicked", (GCallback)on_close_clicked, app);
''',
    '''    connect_signal(app, app->bury_button, "clicked", (GCallback)on_bury_clicked, app);
    connect_signal(app, app->sync_button, "clicked", (GCallback)on_sync_clicked, app);
    connect_signal(app, app->show_answer_button, "clicked", (GCallback)on_show_answer_clicked, app);
    connect_signal(app, app->close_button, "clicked", (GCallback)on_close_clicked, app);
''',
    "sync signal",
)

text = text.replace('    app->ui.gtk_widget_set_sensitive(app->sync_button, 0);\n', '', 1)

once(
    '    free(app->deck_html);\n    free(app->reviewer_html);\n',
    '    free(app->deck_html);\n    free(app->reviewer_html);\n    free(app->sync_html);\n',
    "sync asset cleanup",
)

once(
    '''int main(int argc, char **argv) {
    App app;
    const char *backend_path = DEFAULT_BACKEND;
    memset(&app, 0, sizeof(app));
    app.log = fopen(LOG_PATH, "a");
    if (!app.log) app.log = stderr;
    snprintf(app.media_base, sizeof(app.media_base), "file://%s/", DEFAULT_MEDIA);
    log_message(&app, "start build=%s anki=%s", KANKI_BUILD_COMMIT, KANKI_ANKI_COMMIT);

    if (argc > 2 && strcmp(argv[1], "--backend") == 0) backend_path = argv[2];
''',
    '''int main(int argc, char **argv) {
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
            fprintf(stderr, "usage: %s [--backend PATH] [--start-sync] [--sync-status CODE]\\n", argv[0]);
            cleanup(&app);
            return 64;
        }
    }
''',
    "main argument parsing",
)

once(
    '''    app.deck_html = read_file(DECK_PAGE);
    app.reviewer_html = read_file(REVIEWER_PAGE);
    if (!app.deck_html || !app.reviewer_html) {
''',
    '''    app.deck_html = read_file(DECK_PAGE);
    app.reviewer_html = read_file(REVIEWER_PAGE);
    app.sync_html = read_file(SYNC_PAGE);
    if (!app.deck_html || !app.reviewer_html || !app.sync_html) {
''',
    "sync asset read",
)

once(
    '''    load_decks(&app);
    if (app.ui.gtk_widget_grab_focus) app.ui.gtk_widget_grab_focus(app.web_view);
    app.ui.gtk_main();
    cleanup(&app);
    return 0;
}
''',
    '''    if (app.start_sync) load_sync(&app);
    else load_decks(&app);
    if (app.ui.gtk_widget_grab_focus) app.ui.gtk_widget_grab_focus(app.web_view);
    app.ui.gtk_main();
    exit_status = app.requested_sync;
    cleanup(&app);
    return exit_status;
}
''',
    "sync startup and exit status",
)

PATH.write_text(text)
