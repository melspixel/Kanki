#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int fake_pipeline;
static int fake_source;
static int fake_bus;
static int fake_message;

static void log_line(const char *label, const char *value) {
    const char *path = getenv("KANKI_FAKE_GST_LOG");
    FILE *output;
    if (!path) return;
    output = fopen(path, "a");
    if (!output) return;
    fprintf(output, "%s=%s\n", label, value ? value : "");
    fclose(output);
}

void gst_init(int *argc, char ***argv) {
    (void)argc;
    (void)argv;
    log_line("gst_init", "called");
}

void *gst_parse_launch(const char *description, void **error) {
    if (error) *error = NULL;
    log_line("pipeline", description);
    return &fake_pipeline;
}

void *gst_bin_get_by_name(void *pipeline, const char *name) {
    (void)pipeline;
    log_line("element", name);
    return &fake_source;
}

int gst_element_set_state(void *element, int state) {
    char value[32];
    (void)element;
    snprintf(value, sizeof(value), "%d", state);
    log_line("state", value);
    return 1;
}

void *gst_element_get_bus(void *element) {
    (void)element;
    return &fake_bus;
}

void *gst_bus_poll(void *bus, unsigned int types, int64_t timeout) {
    (void)bus;
    (void)timeout;
    if (types == (1u << 1)) return NULL;
    if (types == (1u << 0)) return &fake_message;
    return NULL;
}

void gst_message_parse_error(void *message, void **error, char **debug) {
    (void)message;
    if (error) *error = NULL;
    if (debug) *debug = NULL;
}

void gst_object_unref(void *object) {
    (void)object;
}

void gst_mini_object_unref(void *object) {
    (void)object;
}
