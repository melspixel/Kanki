#define _POSIX_C_SOURCE 200809L
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kap_core.h"

struct KapCore { int opened; int media_polls; };

static char *copy_json(const char *s) {
    size_t n = strlen(s) + 1;
    char *out = malloc(n);
    if (out) memcpy(out, s, n);
    return out;
}

void kap_string_free(char *value) { free(value); }

KapCore *kap_core_new(char **error_out) {
    KapCore *core = calloc(1, sizeof(*core));
    if (error_out) *error_out = NULL;
    return core;
}

void kap_core_free(KapCore *core) { free(core); }

char *kap_open_collection_json(KapCore *core, const char *collection,
                               const char *media, const char *media_db) {
    (void)collection; (void)media; (void)media_db;
    if (!core) return copy_json("{\"ok\":false,\"error\":\"no core\"}");
    core->opened = 1;
    return copy_json("{\"ok\":true,\"data\":{\"opened\":true},\"error\":null}");
}

char *kap_close_collection_json(KapCore *core) {
    if (core) core->opened = 0;
    return copy_json("{\"ok\":true,\"data\":{\"closed\":true},\"error\":null}");
}

char *kap_sync_collection_json(KapCore *core, const char *hkey, const char *endpoint,
                               uint8_t sync_media, uint32_t timeout) {
    char buffer[512];
    const char *raw = getenv("KAP_FAKE_SYNC_REQUIRED");
    long required = raw ? strtol(raw, NULL, 10) : 0;
    (void)endpoint; (void)sync_media; (void)timeout;
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
    (void)endpoint; (void)upload; (void)server_usn; (void)has_server_media_usn; (void)timeout;
    if (!core || !core->opened || !hkey || strcmp(hkey, "fixture-secret") != 0) {
        return copy_json("{\"ok\":false,\"data\":null,\"error\":\"bad fake auth\"}");
    }
    return copy_json("{\"ok\":true,\"data\":{\"completed\":true},\"error\":null}");
}

char *kap_media_sync_status_json(KapCore *core) {
    const char *active_raw = getenv("KAP_FAKE_MEDIA_ACTIVE_ONCE");
    int active = core && active_raw && strcmp(active_raw, "1") == 0 && core->media_polls++ == 0;
    return copy_json(active
        ? "{\"ok\":true,\"data\":{\"active\":true},\"error\":null}"
        : "{\"ok\":true,\"data\":{\"active\":false},\"error\":null}");
}

char *kap_abort_sync_json(KapCore *core) {
    (void)core;
    return copy_json("{\"ok\":true,\"data\":{\"aborted\":true},\"error\":null}");
}
