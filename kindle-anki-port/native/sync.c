#define _POSIX_C_SOURCE 200809L

#include <dlfcn.h>
#include <errno.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "kap_core.h"

typedef struct {
    void (*string_free)(char *);
    KapCore *(*core_new)(char **);
    void (*core_free)(KapCore *);
    char *(*open_collection)(KapCore *, const char *, const char *, const char *);
    char *(*close_collection)(KapCore *);
    char *(*sync_collection)(KapCore *, const char *, const char *, uint8_t, uint32_t);
    char *(*full_sync)(KapCore *, const char *, const char *, uint8_t, int32_t, uint8_t, uint32_t);
    char *(*media_status)(KapCore *);
    char *(*abort_sync)(KapCore *);
} CoreApi;

static volatile sig_atomic_t g_abort = 0;

static void on_signal(int signal_number) {
    (void)signal_number;
    g_abort = 1;
}

static int load_symbol(void *handle, const char *name, void **slot) {
    *slot = dlsym(handle, name);
    if (*slot == NULL) {
        fprintf(stderr, "missing backend symbol %s: %s\n", name, dlerror());
        return 0;
    }
    return 1;
}

#define LOAD(api, handle, member, name) \
    do { if (!load_symbol((handle), (name), (void **)&((api)->member))) return 0; } while (0)

static int load_api(void *handle, CoreApi *api) {
    memset(api, 0, sizeof(*api));
    LOAD(api, handle, string_free, "kap_string_free");
    LOAD(api, handle, core_new, "kap_core_new");
    LOAD(api, handle, core_free, "kap_core_free");
    LOAD(api, handle, open_collection, "kap_open_collection_json");
    LOAD(api, handle, close_collection, "kap_close_collection_json");
    LOAD(api, handle, sync_collection, "kap_sync_collection_json");
    LOAD(api, handle, full_sync, "kap_full_sync_json");
    LOAD(api, handle, media_status, "kap_media_sync_status_json");
    LOAD(api, handle, abort_sync, "kap_abort_sync_json");
    return 1;
}

static int json_ok(const char *json) {
    return json != NULL && strstr(json, "\"ok\":true") != NULL;
}

static int json_bool(const char *json, const char *name, int *found) {
    char needle[128];
    const char *position;
    snprintf(needle, sizeof(needle), "\"%s\":", name);
    position = json ? strstr(json, needle) : NULL;
    if (position == NULL) { if (found) *found = 0; return 0; }
    position += strlen(needle);
    while (*position == ' ' || *position == '\t') position += 1;
    if (found) *found = 1;
    return strncmp(position, "true", 4) == 0;
}

static int json_integer(const char *json, const char *name, int *found) {
    char needle[128];
    const char *position;
    char *end = NULL;
    long value;
    snprintf(needle, sizeof(needle), "\"%s\":", name);
    position = json ? strstr(json, needle) : NULL;
    if (position == NULL) { if (found) *found = 0; return 0; }
    position += strlen(needle);
    errno = 0;
    value = strtol(position, &end, 10);
    if (errno || end == position || value < INT32_MIN || value > INT32_MAX) {
        if (found) *found = 0;
        return 0;
    }
    if (found) *found = 1;
    return (int)value;
}

static void sleep_millis(long millis) {
    struct timespec delay;
    delay.tv_sec = millis / 1000;
    delay.tv_nsec = (millis % 1000) * 1000000L;
    while (nanosleep(&delay, &delay) < 0 && errno == EINTR && !g_abort) {}
}

static int print_reply(CoreApi *api, char *reply) {
    int ok = json_ok(reply);
    if (reply != NULL) {
        puts(reply);
        api->string_free(reply);
    }
    return ok;
}

static int wait_for_media(CoreApi *api, KapCore *core) {
    while (!g_abort) {
        char *reply = api->media_status(core);
        int found = 0;
        int active;
        if (!json_ok(reply)) {
            print_reply(api, reply);
            return 1;
        }
        active = json_bool(reply, "active", &found);
        print_reply(api, reply);
        if (!found || !active) return 0;
        sleep_millis(250);
    }
    {
        char *reply = api->abort_sync(core);
        print_reply(api, reply);
    }
    return 130;
}

static int self_test(void) {
    int found = 0;
    const char *sample = "{\"ok\":true,\"data\":{\"required\":3,\"active\":true}}";
    if (!json_ok(sample)) return 1;
    if (json_integer(sample, "required", &found) != 3 || !found) return 1;
    if (!json_bool(sample, "active", &found) || !found) return 1;
    puts("kap-sync self-test: ok");
    return 0;
}

static void usage(const char *program) {
    fprintf(stderr,
            "usage: %s --backend LIB --collection FILE --media DIR --media-db FILE "
            "[--full-upload|--full-download] [--server-usn N] [--no-media]\n",
            program);
}

int main(int argc, char **argv) {
    const char *backend_path = NULL;
    const char *collection = NULL;
    const char *media = NULL;
    const char *media_db = NULL;
    const char *hkey = getenv("KAP_SYNC_HKEY");
    const char *endpoint = getenv("KAP_SYNC_ENDPOINT");
    int mode = 0;
    int sync_media = 1;
    int has_server_usn = 0;
    int server_usn = 0;
    uint32_t timeout = 120;
    void *library = NULL;
    CoreApi api;
    KapCore *core = NULL;
    char *error = NULL;
    char *reply = NULL;
    int status = 0;
    int index;
    struct sigaction action;

    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return self_test();
    for (index = 1; index < argc; index += 1) {
        if (strcmp(argv[index], "--backend") == 0 && index + 1 < argc) backend_path = argv[++index];
        else if (strcmp(argv[index], "--collection") == 0 && index + 1 < argc) collection = argv[++index];
        else if (strcmp(argv[index], "--media") == 0 && index + 1 < argc) media = argv[++index];
        else if (strcmp(argv[index], "--media-db") == 0 && index + 1 < argc) media_db = argv[++index];
        else if (strcmp(argv[index], "--full-upload") == 0) {
            if (mode != 0 && mode != 1) { usage(argv[0]); return 64; }
            mode = 1;
        } else if (strcmp(argv[index], "--full-download") == 0) {
            if (mode != 0 && mode != 2) { usage(argv[0]); return 64; }
            mode = 2;
        }
        else if (strcmp(argv[index], "--no-media") == 0) sync_media = 0;
        else if (strcmp(argv[index], "--server-usn") == 0 && index + 1 < argc) {
            char *end = NULL;
            long value = strtol(argv[++index], &end, 10);
            if (!end || *end || value < INT32_MIN || value > INT32_MAX) { usage(argv[0]); return 64; }
            server_usn = (int)value;
            has_server_usn = 1;
        } else if (strcmp(argv[index], "--timeout") == 0 && index + 1 < argc) {
            char *end = NULL;
            unsigned long value = strtoul(argv[++index], &end, 10);
            if (!end || *end || value > UINT32_MAX) { usage(argv[0]); return 64; }
            timeout = (uint32_t)value;
        } else if (strcmp(argv[index], "--interactive") == 0) {
            /* Accepted for launcher compatibility; decisions remain explicit. */
        } else { usage(argv[0]); return 64; }
    }
    if (!backend_path || !collection || !media || !media_db || !hkey || !*hkey) {
        usage(argv[0]);
        return 64;
    }

    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);

    library = dlopen(backend_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) { fprintf(stderr, "unable to load %s: %s\n", backend_path, dlerror()); return 65; }
    if (!load_api(library, &api)) { dlclose(library); return 66; }
    core = api.core_new(&error);
    if (!core) {
        fprintf(stderr, "backend initialization failed: %s\n", error ? error : "unknown");
        if (error) api.string_free(error);
        dlclose(library);
        return 67;
    }

    reply = api.open_collection(core, collection, media, media_db);
    if (!print_reply(&api, reply)) { status = 68; goto cleanup; }

    if (mode == 0) {
        int found = 0;
        int required;
        reply = api.sync_collection(core, hkey, endpoint ? endpoint : "", (uint8_t)sync_media, timeout);
        if (!json_ok(reply)) { print_reply(&api, reply); status = 1; goto cleanup; }
        required = json_integer(reply, "required", &found);
        print_reply(&api, reply);
        if (!found) { status = 1; goto cleanup; }
        if (required == 0) status = sync_media ? wait_for_media(&api, core) : 0;
        else if (required == 2) status = 75;
        else if (required == 3) status = 76;
        else if (required == 4) status = 77;
        else status = 78;
    } else {
        reply = api.full_sync(core, hkey, endpoint ? endpoint : "", (uint8_t)(mode == 1),
                              server_usn, (uint8_t)has_server_usn, timeout);
        if (!print_reply(&api, reply)) { status = 1; goto cleanup; }
        status = has_server_usn && sync_media ? wait_for_media(&api, core) : 0;
    }

cleanup:
    reply = api.close_collection(core);
    if (reply) print_reply(&api, reply);
    api.core_free(core);
    dlclose(library);
    return status;
}
