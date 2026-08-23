#define _POSIX_C_SOURCE 200809L
#define KAP_LIPC_SET_PROP "/proc/self/exe"

#include <errno.h>
#include <signal.h>
#include <stdarg.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

typedef struct App {
    int marker;
} App;

static void log_line(App *app, const char *format, ...) {
    va_list args;
    (void)app;
    va_start(args, format);
    vfprintf(stderr, format, args);
    fputc('\n', stderr);
    va_end(args);
}

static void app_part3_stop_audio(App *app) {
    app->marker += 1;
}

static void app_part3_load_decks(App *app) {
    app->marker += 10;
}

static void app_part3_dispatch_uri(App *app, const char *uri) {
    (void)uri;
    app->marker += 100;
}

#include "../native/app_platform.inc"

static int record_child_arguments(int argc, char **argv) {
    const char *log_path = getenv("KAP_TEST_LIPC_LOG");
    FILE *log;
    int index;
    if (argc != 5 || strcmp(argv[1], "-s") != 0 || !log_path || !*log_path) return 90;
    log = fopen(log_path, "a");
    if (!log) return 91;
    for (index = 1; index < argc; index += 1) fprintf(log, "%s\n", argv[index]);
    if (fclose(log) != 0) return 92;
    return 0;
}

static int read_file(const char *path, char *buffer, size_t capacity) {
    FILE *file = fopen(path, "r");
    size_t used;
    if (!file) return 0;
    used = fread(buffer, 1, capacity - 1, file);
    if (ferror(file)) {
        fclose(file);
        return 0;
    }
    buffer[used] = '\0';
    return fclose(file) == 0;
}

int main(int argc, char **argv) {
    static const char expected[] =
        "-s\n"
        "com.lab126.keyboard\n"
        "close\n"
        "com.melspixel.kindleankiport\n"
        "-s\n"
        "com.lab126.keyboard\n"
        "open\n"
        "com.melspixel.kindleankiport:abc:1\n"
        "-s\n"
        "com.lab126.keyboard\n"
        "close\n"
        "com.melspixel.kindleankiport\n";
    char log_path[] = "/tmp/kap-platform-adapter.XXXXXX";
    char actual[1024];
    App app;
    int fd;

    if (argc > 1) return record_child_arguments(argc, argv);

    fd = mkstemp(log_path);
    if (fd < 0) return 1;
    close(fd);
    if (setenv("KAP_TEST_LIPC_LOG", log_path, 1) != 0) {
        unlink(log_path);
        return 2;
    }

    memset(&app, 0, sizeof(app));
    if (strcmp(KAP_WINDOW_TITLE,
               "L:A_N:application_ID:com.melspixel.kindleankiport_PC:N") != 0) return 3;
    if (!kap_uri_operation_is("kap://v1/ime/open?request_id=1", "ime/open")) return 4;
    if (kap_uri_operation_is("kap://v1/ime/open-extra", "ime/open")) return 5;

    /* The first deck load normalizes a keyboard left visible by a crashed
     * previous process. */
    load_decks(&app);
    if (!g_kap_keyboard_state_known || g_kap_keyboard_requested) return 6;

    dispatch_uri(&app, "kap://v1/ime/open?request_id=open");
    if (!g_kap_keyboard_requested) return 7;
    dispatch_uri(&app, "kap://v1/ime/open?request_id=duplicate");

    /* Reveal must close before the semantic operation is delegated. */
    dispatch_uri(&app, "kap://v1/review/reveal?typed=x");
    if (g_kap_keyboard_requested) return 8;
    stop_audio(&app);
    if (app.marker != 111) return 9;

    if (!read_file(log_path, actual, sizeof(actual))) return 10;
    unlink(log_path);
    if (strcmp(actual, expected) != 0) {
        fprintf(stderr, "unexpected lipc argument log:\n%s", actual);
        return 11;
    }

    puts("test_platform_adapter: ok (startup close, open, de-duplicate, reveal close)");
    return 0;
}
