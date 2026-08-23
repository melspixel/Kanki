#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

static volatile sig_atomic_t raised = 0;
static void handle_usr1(int value) { (void)value; raised = 1; }

static void trace_event(const char *event) {
    const char *path = getenv("KAP_FAKE_TRACE");
    FILE *file;
    if (!path || !*path) return;
    file = fopen(path, "a");
    if (!file) return;
    fprintf(file, "%s %ld\n", event, (long)getpid());
    fclose(file);
}

int main(int argc, char **argv) {
    const char *marker = getenv("KAP_FAKE_MARKER");
    const char *mode = getenv("KAP_FAKE_MODE");
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_usr1;
    sigaction(SIGUSR1, &action, NULL);
    trace_event("start");
    if (mode && strcmp(mode, "wait-for-raise") == 0) {
        int count;
        for (count = 0; count < 100 && !raised; count += 1) {
            struct timespec delay = {0, 20000000L};
            nanosleep(&delay, NULL);
        }
        if (raised && marker) {
            FILE *f = fopen(marker, "w");
            if (f) { fputs("raised\n", f); fclose(f); }
        }
        trace_event(raised ? "raised" : "timeout");
        return raised ? 0 : 3;
    }
    if (mode && strcmp(mode, "wait") == 0) {
        int count;
        for (count = 0; count < 100; count += 1) {
            struct timespec delay = {0, 20000000L};
            nanosleep(&delay, NULL);
        }
    }
    if (marker) {
        FILE *f = fopen(marker, "w");
        if (f) { fputs("ran\n", f); fclose(f); }
    }
    trace_event("exit");
    (void)argc; (void)argv;
    return 0;
}
