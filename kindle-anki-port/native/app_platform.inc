/*
 * Kindle/Lab126 platform behavior adapter.
 *
 * Behavioral references and attribution policy are recorded in
 * docs/REFERENCE_IMPLEMENTATIONS.md. This implementation is independently
 * written for Kanki's C/JavaScript protocol and does not import another
 * project's runtime code.
 */

#ifndef KAP_APP_ID
#define KAP_APP_ID "com.melspixel.kindleankiport"
#endif
#define KAP_WINDOW_TITLE "L:A_N:application_ID:" KAP_APP_ID "_PC:N"
#define KAP_LIPC_SET_PROP "/usr/bin/lipc-set-prop"
#define KAP_KEYBOARD_PUBLISHER "com.lab126.keyboard"
#define KAP_KEYBOARD_LAYOUT "abc"
#define KAP_KEYBOARD_MODE "1"
#define KAP_PLATFORM_CHILD_TIMEOUT_MS 2000L
#define KAP_PLATFORM_CHILD_POLL_MS 25L

static int g_kap_keyboard_requested = 0;

static int kap_uri_operation_is(const char *uri, const char *operation) {
    static const char prefix[] = "kap://v1/";
    const char *start;
    const char *end;
    size_t actual_length;
    size_t expected_length;
    if (!uri || !operation || strncmp(uri, prefix, sizeof(prefix) - 1) != 0) return 0;
    start = uri + sizeof(prefix) - 1;
    end = strchr(start, '?');
    actual_length = end ? (size_t)(end - start) : strlen(start);
    expected_length = strlen(operation);
    return actual_length == expected_length && strncmp(start, operation, expected_length) == 0;
}

static int kap_wait_child_bounded(App *app, pid_t pid, int *status_out) {
    long waited_ms = 0;
    int status = 0;
    for (;;) {
        pid_t result = waitpid(pid, &status, WNOHANG);
        if (result == pid) {
            if (status_out) *status_out = status;
            return 1;
        }
        if (result < 0) {
            if (errno == EINTR) continue;
            if (errno == ECHILD) {
                if (status_out) *status_out = status;
                return 1;
            }
            log_line(app, "platform child wait failed pid=%ld: %s",
                     (long)pid, strerror(errno));
            return 0;
        }
        if (waited_ms >= KAP_PLATFORM_CHILD_TIMEOUT_MS) break;
        {
            struct timespec delay;
            delay.tv_sec = 0;
            delay.tv_nsec = KAP_PLATFORM_CHILD_POLL_MS * 1000000L;
            while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {}
        }
        waited_ms += KAP_PLATFORM_CHILD_POLL_MS;
    }

    log_line(app, "platform child timed out pid=%ld; forcing SIGKILL", (long)pid);
    if (kill(pid, SIGKILL) < 0 && errno != ESRCH) {
        log_line(app, "platform child SIGKILL failed pid=%ld: %s",
                 (long)pid, strerror(errno));
    }
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    if (status_out) *status_out = status;
    return 0;
}

static int kap_lipc_set_string(App *app, const char *property, const char *value) {
    pid_t child;
    int status = 0;
    if (!property || !value) return 0;

    child = fork();
    if (child == 0) {
        execl(KAP_LIPC_SET_PROP, KAP_LIPC_SET_PROP, "-s",
              KAP_KEYBOARD_PUBLISHER, property, value, (char *)NULL);
        _exit(127);
    }
    if (child < 0) {
        log_line(app, "unable to fork %s: %s", KAP_LIPC_SET_PROP, strerror(errno));
        return 0;
    }
    if (!kap_wait_child_bounded(app, child, &status)) return 0;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        log_line(app, "%s property=%s failed status=%d",
                 KAP_LIPC_SET_PROP, property,
                 WIFEXITED(status) ? WEXITSTATUS(status) : -1);
        return 0;
    }
    return 1;
}

static int kap_set_keyboard_visible(App *app, int visible) {
    char open_value[160];
    int ok;
    visible = visible != 0;
    if (visible == g_kap_keyboard_requested) return 1;

    if (visible) {
        if (snprintf(open_value, sizeof(open_value), "%s:%s:%s",
                     KAP_APP_ID, KAP_KEYBOARD_LAYOUT, KAP_KEYBOARD_MODE) >=
            (int)sizeof(open_value)) {
            log_line(app, "keyboard application identity is too long");
            return 0;
        }
        ok = kap_lipc_set_string(app, "open", open_value);
    } else {
        ok = kap_lipc_set_string(app, "close", KAP_APP_ID);
    }

    if (ok) {
        g_kap_keyboard_requested = visible;
        log_line(app, "keyboard requested=%d", visible);
    }
    return ok;
}

/* app_part3 is included with these three symbols renamed. The wrappers below
 * add platform behavior without copying or forking the semantic reviewer code. */
static void stop_audio(App *app) {
    (void)kap_set_keyboard_visible(app, 0);
    app_part3_stop_audio(app);
}

static void load_decks(App *app) {
    (void)kap_set_keyboard_visible(app, 0);
    app_part3_load_decks(app);
}

static void dispatch_uri(App *app, const char *uri) {
    if (kap_uri_operation_is(uri, "ime/open")) {
        (void)kap_set_keyboard_visible(app, 1);
        return;
    }
    if (kap_uri_operation_is(uri, "ime/close")) {
        (void)kap_set_keyboard_visible(app, 0);
        return;
    }

    /* Closing before reveal avoids leaving the Lab126 keyboard over the answer
     * side if WebKit does not deliver blur during the DOM replacement. */
    if (kap_uri_operation_is(uri, "review/reveal") ||
        kap_uri_operation_is(uri, "app/back") ||
        kap_uri_operation_is(uri, "app/close")) {
        (void)kap_set_keyboard_visible(app, 0);
    }
    app_part3_dispatch_uri(app, uri);
}
