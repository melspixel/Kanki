#define _POSIX_C_SOURCE 200809L
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "kap_core.h"

typedef char *(*build_info_fn)(void);
typedef KapCore *(*core_new_fn)(char **);
typedef void (*core_free_fn)(KapCore *);
typedef void (*string_free_fn)(char *);

static void *need(void *handle, const char *name) {
    void *value = dlsym(handle, name);
    if (!value) {
        fprintf(stderr, "missing symbol %s: %s\n", name, dlerror());
        exit(2);
    }
    return value;
}

int main(int argc, char **argv) {
    void *handle;
    build_info_fn build_info;
    core_new_fn core_new;
    core_free_fn core_free;
    string_free_fn string_free;
    char *error = NULL;
    char *json;
    KapCore *core;
    if (argc != 2) {
        fprintf(stderr, "usage: %s /path/to/libanki-kindle.so\n", argv[0]);
        return 64;
    }
    handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
    if (!handle) {
        fprintf(stderr, "dlopen failed: %s\n", dlerror());
        return 1;
    }
    build_info = (build_info_fn)need(handle, "kap_build_info_json");
    core_new = (core_new_fn)need(handle, "kap_core_new");
    core_free = (core_free_fn)need(handle, "kap_core_free");
    string_free = (string_free_fn)need(handle, "kap_string_free");
    json = build_info();
    if (!json || !strstr(json, "\"source_driven_port\":true")) {
        fprintf(stderr, "unexpected build info: %s\n", json ? json : "NULL");
        if (json) string_free(json);
        dlclose(handle);
        return 3;
    }
    puts(json);
    string_free(json);
    core = core_new(&error);
    if (!core) {
        fprintf(stderr, "core init failed: %s\n", error ? error : "unknown");
        if (error) string_free(error);
        dlclose(handle);
        return 4;
    }
    core_free(core);
    dlclose(handle);
    puts("qemu backend smoke: ok");
    return 0;
}
