#include "kanki_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int require_ok(const char *label, char *json) {
    if (!json) {
        fprintf(stderr, "%s returned NULL\n", label);
        return 0;
    }
    printf("%s=%s\n", label, json);
    int ok = strstr(json, "\"ok\":true") != NULL;
    kanki_string_free(json);
    return ok;
}

int main(int argc, char **argv) {
    if (argc != 4) {
        fprintf(stderr, "usage: %s COLLECTION MEDIA MEDIA_DB\n", argv[0]);
        return 64;
    }
    if (!require_ok("build", kanki_build_info_json())) return 1;

    char *error = NULL;
    KankiCore *core = kanki_core_new(&error);
    if (!core) {
        fprintf(stderr, "core init failed: %s\n", error ? error : "unknown");
        if (error) kanki_string_free(error);
        return 2;
    }

    int ok = 1;
    ok &= require_ok("open", kanki_open_collection_json(core, argv[1], argv[2], argv[3]));
    ok &= require_ok("decks", kanki_deck_tree_json(core));
    ok &= require_ok("health", kanki_health_json(core));
    ok &= require_ok("close", kanki_close_collection_json(core));
    kanki_core_free(core);
    return ok ? 0 : 3;
}
