#define _POSIX_C_SOURCE 200809L
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>

static volatile sig_atomic_t raised = 0;
static void handle_usr1(int value) { (void)value; raised = 1; }

int main(int argc, char **argv) {
    const char *marker = getenv("KAP_FAKE_MARKER");
    const char *mode = getenv("KAP_FAKE_MODE");
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = handle_usr1;
    sigaction(SIGUSR1, &action, NULL);
    if (mode && strcmp(mode, "wait-for-raise") == 0) {
        int count;
        for (count = 0; count < 100 && !raised; count += 1) {
            struct timespec delay = {0, 20000000L};
            nanosleep(&delay, NULL);
        }
        if (raised && marker) { FILE *f = fopen(marker, "w"); if (f) { fputs("raised\n", f); fclose(f); } }
        return raised ? 0 : 3;
    }
    if (marker) { FILE *f = fopen(marker, "w"); if (f) { fputs("ran\n", f); fclose(f); } }
    (void)argc; (void)argv;
    return 0;
}
