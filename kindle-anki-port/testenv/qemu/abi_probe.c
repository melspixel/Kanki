#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>

static const char *const required_symbols[] = {
    "kap_open_collection_json",
    "kap_deck_tree_json",
    "kap_set_current_deck_json",
    "kap_next_question_json",
    "kap_reveal_answer_json",
    "kap_answer_json",
    "kap_bury_current_json",
    "kap_close_collection_json",
    "kap_free_string",
    NULL
};

int main(int argc, char **argv) {
    const char *path = argc > 1 ? argv[1] : "./libanki-kindle.so";
    void *handle = dlopen(path, RTLD_NOW | RTLD_LOCAL);
    const char *const *name;
    int failures = 0;
    if (!handle) {
        fprintf(stderr, "dlopen(%s): %s\n", path, dlerror());
        return 2;
    }
    for (name = required_symbols; *name; ++name) {
        dlerror();
        if (!dlsym(handle, *name)) {
            const char *error = dlerror();
            fprintf(stderr, "missing %s: %s\n", *name, error ? error : "unknown");
            failures++;
        } else {
            printf("found=%s\n", *name);
        }
    }
    dlclose(handle);
    return failures ? 3 : 0;
}
