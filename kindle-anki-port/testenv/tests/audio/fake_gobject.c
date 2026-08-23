#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_line(const char *line) {
    const char *path = getenv("KAP_FAKE_GST_LOG");
    FILE *file;
    if (!path) return;
    file = fopen(path, "a");
    if (!file) return;
    fputs(line, file);
    fputc('\n', file);
    fclose(file);
}

void g_object_set(void *object, const char *first_property_name, ...) {
    va_list args;
    char line[4096];
    (void)object;
    va_start(args, first_property_name);
    if (first_property_name && strcmp(first_property_name, "uri") == 0) {
        const char *value = va_arg(args, const char *);
        snprintf(line, sizeof(line), "property=uri value=%s", value ? value : "");
        log_line(line);
    } else if (first_property_name && strcmp(first_property_name, "audio-sink") == 0) {
        (void)va_arg(args, void *);
        log_line("property=audio-sink");
    }
    va_end(args);
}
