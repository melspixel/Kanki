#define _POSIX_C_SOURCE 200809L

#include <dlfcn.h>
#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include "kanki_bridge.h"
#include "kanki_sync_bridge.h"

#define KANKI_DIR "/mnt/us/extensions/kanki"
#define DEFAULT_LIBRARY KANKI_DIR "/libanki-kanki.so"
#define DEFAULT_CONFIG KANKI_DIR "/config.ini"
#define DEFAULT_COLLECTION "/mnt/us/anki_data/collection.anki2"
#define DEFAULT_MEDIA "/mnt/us/anki_data/collection.media"
#define DEFAULT_MEDIA_DB "/mnt/us/anki_data/media.db2"
#define VALUE_CAPACITY 1024

struct Api {
    void (*string_free)(char *);
    KankiSyncCore *(*core_new)(char **);
    void (*core_free)(KankiSyncCore *);
    char *(*open_collection)(KankiSyncCore *, const char *, const char *, const char *);
    char *(*close_collection)(KankiSyncCore *);
    char *(*sync_collection)(KankiSyncCore *, const char *, const char *, uint8_t);
    char *(*full_sync)(KankiSyncCore *, const char *, const char *, uint8_t, int32_t, uint8_t);
    char *(*media_status)(KankiSyncCore *);
    char *(*abort_sync)(KankiSyncCore *);
};

static int load_symbol(void *library, const char *name, void *target, size_t target_size) {
    void *symbol;
    const char *error;
    dlerror();
    symbol = dlsym(library, name);
    error = dlerror();
    if (error || !symbol || target_size != sizeof(symbol)) {
        fprintf(stderr, "sync: missing %s: %s\n", name, error ? error : "not found");
        return 0;
    }
    memcpy(target, &symbol, sizeof(symbol));
    return 1;
}

#define LOAD(handle, api, field, name) \
    do { if (!load_symbol((handle), (name), &(api)->field, sizeof((api)->field))) return 0; } while (0)

static int load_api(void *library, struct Api *api) {
    memset(api, 0, sizeof(*api));
    LOAD(library, api, string_free, "kanki_string_free");
    LOAD(library, api, core_new, "kanki_sync_core_new");
    LOAD(library, api, core_free, "kanki_sync_core_free");
    LOAD(library, api, open_collection, "kanki_sync_open_collection_json");
    LOAD(library, api, close_collection, "kanki_sync_close_collection_json");
    LOAD(library, api, sync_collection, "kanki_sync_collection_json");
    LOAD(library, api, full_sync, "kanki_sync_full_json");
    LOAD(library, api, media_status, "kanki_sync_media_status_json");
    LOAD(library, api, abort_sync, "kanki_sync_abort_json");
    return 1;
}

static char *trim(char *value) {
    char *end;
    while (*value == ' ' || *value == '\t') value++;
    end = value + strlen(value);
    while (end > value && (end[-1] == ' ' || end[-1] == '\t' || end[-1] == '\r' || end[-1] == '\n')) end--;
    *end = '\0';
    return value;
}

static int read_config_value(const char *path, const char *key, char *output, size_t capacity) {
    FILE *file = fopen(path, "r");
    char line[VALUE_CAPACITY * 2];
    size_t key_length = strlen(key);
    if (!file) return 0;
    while (fgets(line, sizeof(line), file)) {
        char *value = trim(line);
        if (*value == '#' || *value == ';' || *value == '[' || *value == '\0') continue;
        if (strncmp(value, key, key_length) == 0) {
            value += key_length;
            while (*value == ' ' || *value == '\t') value++;
            if (*value != '=') continue;
            value = trim(value + 1);
            if (strlen(value) + 1 > capacity) {
                fclose(file);
                return 0;
            }
            memcpy(output, value, strlen(value) + 1);
            fclose(file);
            return 1;
        }
    }
    fclose(file);
    return 0;
}

static int json_ok(const char *json) {
    return json && strstr(json, "\"ok\":true") != NULL;
}

static int json_string_field(const char *json, const char *key, char *output, size_t capacity) {
    char pattern[128];
    const char *start;
    const char *end;
    if (snprintf(pattern, sizeof(pattern), "\"%s\":\"", key) >= (int)sizeof(pattern)) return 0;
    start = strstr(json, pattern);
    if (!start) return 0;
    start += strlen(pattern);
    end = start;
    while (*end && *end != '"') {
        if (*end == '\\' && end[1]) end += 2;
        else end++;
    }
    if (*end != '"' || (size_t)(end - start) + 1 > capacity) return 0;
    memcpy(output, start, (size_t)(end - start));
    output[end - start] = '\0';
    return 1;
}

static int json_int_field(const char *json, const char *key, int32_t *output) {
    char pattern[128];
    const char *start;
    char *end;
    long value;
    if (snprintf(pattern, sizeof(pattern), "\"%s\":", key) >= (int)sizeof(pattern)) return 0;
    start = strstr(json, pattern);
    if (!start) return 0;
    start += strlen(pattern);
    value = strtol(start, &end, 10);
    if (end == start || value < INT32_MIN || value > INT32_MAX) return 0;
    *output = (int32_t)value;
    return 1;
}

static void print_redacted_response(const char *label, const char *response) {
    char required[64];
    if (!response) {
        fprintf(stderr, "%s=null\n", label);
    } else if (json_string_field(response, "required", required, sizeof(required))) {
        fprintf(stderr, "%s=ok required=%s\n", label, required);
    } else {
        fprintf(stderr, "%s=%s\n", label, json_ok(response) ? "ok" : "failed");
    }
}

static int wait_for_media(struct Api *api, KankiSyncCore *core) {
    int attempts;
    for (attempts = 0; attempts < 600; attempts++) {
        char *status = api->media_status(core);
        int active = status && strstr(status, "\"active\":true") != NULL;
        if (!json_ok(status)) {
            print_redacted_response("media_status", status);
            if (status) api->string_free(status);
            return 0;
        }
        if (!active) {
            api->string_free(status);
            return 1;
        }
        api->string_free(status);
        sleep(1);
    }
    fprintf(stderr, "media_status=timeout\n");
    return 0;
}

int main(int argc, char **argv) {
    const char *library_path = DEFAULT_LIBRARY;
    const char *config_path = DEFAULT_CONFIG;
    int full_direction = 0;
    char hkey[VALUE_CAPACITY];
    char endpoint[VALUE_CAPACITY];
    char required[64];
    int32_t server_media_usn = 0;
    int have_server_media_usn = 0;
    void *library;
    struct Api api;
    KankiSyncCore *core;
    char *error = NULL;
    char *response = NULL;
    int exit_code = 1;
    int i;

    hkey[0] = '\0';
    endpoint[0] = '\0';
    for (i = 1; i < argc; i++) {
        if (strcmp(argv[i], "--full-upload") == 0) full_direction = 1;
        else if (strcmp(argv[i], "--full-download") == 0) full_direction = -1;
        else if (strcmp(argv[i], "--library") == 0 && i + 1 < argc) library_path = argv[++i];
        else if (strcmp(argv[i], "--config") == 0 && i + 1 < argc) config_path = argv[++i];
        else {
            fprintf(stderr, "usage: %s [--full-upload|--full-download] [--library PATH] [--config PATH]\n", argv[0]);
            return 64;
        }
    }
    if (!read_config_value(config_path, "hkey", hkey, sizeof(hkey)) || !*hkey) {
        fprintf(stderr, "sync: missing hkey in %s\n", config_path);
        return 65;
    }
    (void)read_config_value(config_path, "endpoint", endpoint, sizeof(endpoint));

    library = dlopen(library_path, RTLD_NOW | RTLD_LOCAL);
    if (!library) {
        fprintf(stderr, "sync: cannot load backend: %s\n", dlerror());
        return 66;
    }
    if (!load_api(library, &api)) {
        dlclose(library);
        return 67;
    }
    core = api.core_new(&error);
    if (!core) {
        fprintf(stderr, "sync: initialization failed: %s\n", error ? error : "unknown");
        if (error) api.string_free(error);
        dlclose(library);
        return 68;
    }

    response = api.open_collection(core, DEFAULT_COLLECTION, DEFAULT_MEDIA, DEFAULT_MEDIA_DB);
    print_redacted_response("sync_open", response);
    if (!json_ok(response)) goto cleanup;
    api.string_free(response);
    response = NULL;

    response = api.sync_collection(core, hkey, endpoint, 1);
    print_redacted_response("sync_collection", response);
    if (!json_ok(response)) goto cleanup;
    required[0] = '\0';
    (void)json_string_field(response, "required", required, sizeof(required));
    have_server_media_usn = json_int_field(response, "server_media_usn", &server_media_usn);
    api.string_free(response);
    response = NULL;

    if (strcmp(required, "full_upload") == 0) full_direction = 1;
    else if (strcmp(required, "full_download") == 0) full_direction = -1;
    else if (strcmp(required, "full_sync") == 0 && full_direction == 0) {
        fprintf(stderr,
                "sync: full sync choice required; rerun with --full-upload or --full-download\n");
        exit_code = 75;
        goto cleanup;
    }

    if (full_direction != 0) {
        response = api.full_sync(core, hkey, endpoint, (uint8_t)(full_direction > 0),
                                 server_media_usn, (uint8_t)have_server_media_usn);
        print_redacted_response(full_direction > 0 ? "full_upload" : "full_download", response);
        if (!json_ok(response)) goto cleanup;
        api.string_free(response);
        response = NULL;
    }
    if (!wait_for_media(&api, core)) goto cleanup;
    exit_code = 0;

cleanup:
    if (response) api.string_free(response);
    response = api.close_collection(core);
    if (response) api.string_free(response);
    api.core_free(core);
    dlclose(library);
    memset(hkey, 0, sizeof(hkey));
    return exit_code;
}
