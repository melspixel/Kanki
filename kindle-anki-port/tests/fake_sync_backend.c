#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kap_core.h"

struct KapCore { int opened; int media_polls; };

static int env_is(const char *name, const char *value) {
    const char *actual = getenv(name);
    return actual != NULL && strcmp(actual, value) == 0;
}

static char *copy_json(const char *s) {
    size_t n = strlen(s) + 1;
    char *out = malloc(n);
    if (out) memcpy(out, s, n);
    return out;
}

static void trace_event(const char *event) {
    const char *path = getenv("KAP_FAKE_TRACE");
    FILE *file;
    if (!path || !*path) return;
    file = fopen(path, "a");
    if (!file) return;
    fputs(event, file);
    fputc('\n', file);
    fclose(file);
}

static void trace_sync_args(const char *kind, const char *endpoint,
                            uint8_t media_or_upload, int32_t server_usn,
                            uint8_t has_server_usn, uint32_t timeout) {
    char line[768];
    snprintf(line, sizeof(line),
             "%s endpoint=%s flag=%u server_usn=%d has_server_usn=%u timeout=%u",
             kind, endpoint ? endpoint : "", (unsigned)media_or_upload,
             (int)server_usn, (unsigned)has_server_usn, (unsigned)timeout);
    trace_event(line);
}

void kap_string_free(char *value) { free(value); }

KapCore *kap_core_new(char **error_out) {
    KapCore *core;
    trace_event("core_new");
    if (env_is("KAP_FAKE_CORE_NEW_FAIL", "1")) {
        if (error_out) *error_out = copy_json("fixture backend initialization failure");
        return NULL;
    }
    core = calloc(1, sizeof(*core));
    if (error_out) *error_out = NULL;
    return core;
}

void kap_core_free(KapCore *core) {
    trace_event("core_free");
    free(core);
}

char *kap_open_collection_json(KapCore *core, const char *collection,
                               const char *media, const char *media_db) {
    (void)collection; (void)media; (void)media_db;
    trace_event("open");
    if (env_is("KAP_FAKE_OPEN_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture open failure\"}");
    }
    if (!core) return copy_json("{\"ok\":false,\"error\":\"no core\"}");
    core->opened = 1;
    return copy_json("{\"ok\":true,\"data\":{\"opened\":true},\"error\":null}");
}

char *kap_close_collection_json(KapCore *core) {
    trace_event("close");
    if (core) core->opened = 0;
    if (env_is("KAP_FAKE_CLOSE_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture close failure\"}");
    }
    return copy_json("{\"ok\":true,\"data\":{\"closed\":true},\"error\":null}");
}

char *kap_sync_collection_json(KapCore *core, const char *hkey, const char *endpoint,
                               uint8_t sync_media, uint32_t timeout) {
    char buffer[512];
    const char *raw = getenv("KAP_FAKE_SYNC_REQUIRED");
    long required = raw ? strtol(raw, NULL, 10) : 0;
    trace_sync_args("sync", endpoint, sync_media, 0, 0, timeout);
    if (env_is("KAP_FAKE_SYNC_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture sync failure\"}");
    }
    if (!core || !core->opened || !hkey || strcmp(hkey, "fixture-secret") != 0) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"bad fake auth\"}");
    }
    snprintf(buffer, sizeof(buffer),
             "{\"ok\":true,\"data\":{\"required\":%ld,\"required_name\":\"fixture\",\"server_media_usn\":17},\"error\":null}",
             required);
    return copy_json(buffer);
}

char *kap_full_sync_json(KapCore *core, const char *hkey, const char *endpoint,
                         uint8_t upload, int32_t server_usn,
                         uint8_t has_server_media_usn, uint32_t timeout) {
    trace_sync_args("full", endpoint, upload, server_usn, has_server_media_usn, timeout);
    if (env_is("KAP_FAKE_FULL_SYNC_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture full sync failure\"}");
    }
    if (!core || !core->opened || !hkey || strcmp(hkey, "fixture-secret") != 0) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"bad fake auth\"}");
    }
    return copy_json("{\"ok\":true,\"data\":{\"completed\":true},\"error\":null}");
}

char *kap_media_sync_status_json(KapCore *core) {
    const char *active_raw = getenv("KAP_FAKE_MEDIA_ACTIVE_ONCE");
    int active;
    trace_event("media_status");
    if (env_is("KAP_FAKE_MEDIA_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture media status failure\"}");
    }
    active = core && (env_is("KAP_FAKE_MEDIA_ACTIVE_FOREVER", "1") ||
             (active_raw && strcmp(active_raw, "1") == 0 && core->media_polls++ == 0));
    return copy_json(active
        ? "{\"ok\":true,\"data\":{\"active\":true},\"error\":null}"
        : "{\"ok\":true,\"data\":{\"active\":false},\"error\":null}");
}

char *kap_abort_sync_json(KapCore *core) {
    (void)core;
    trace_event("abort");
    if (env_is("KAP_FAKE_ABORT_FAIL", "1")) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"fixture abort failure\"}");
    }
    return copy_json("{\"ok\":true,\"data\":{\"aborted\":true},\"error\":null}");
}
