#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_string(const char *name, const char *value) {
    const char *path = getenv("KANKI_FAKE_GST_LOG");
    FILE *output;
    if (!path) return;
    output = fopen(path, "a");
    if (!output) return;
    fprintf(output, "property=%s value=%s\n", name, value ? value : "");
    fclose(output);
}

static void log_speed(const char *name, double value) {
    const char *path = getenv("KANKI_FAKE_GST_LOG");
    FILE *output;
    if (!path) return;
    output = fopen(path, "a");
    if (!output) return;
    fprintf(output, "property=%s value=%.9g\n", name, value);
    fclose(output);
}

void g_object_set(void *object, const char *first_property_name, ...) {
    const char *name = first_property_name;
    va_list arguments;
    (void)object;
    va_start(arguments, first_property_name);
    while (name) {
        if (strcmp(name, "speed") == 0) {
            log_speed(name, va_arg(arguments, double));
        } else {
            log_string(name, va_arg(arguments, const char *));
        }
        name = va_arg(arguments, const char *);
    }
    va_end(arguments);
}
