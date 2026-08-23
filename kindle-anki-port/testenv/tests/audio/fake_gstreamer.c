#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GST_MESSAGE_EOS (1u << 0)
#define GST_MESSAGE_ERROR (1u << 1)

static int dummy_playbin;
static int dummy_sink;
static int dummy_bus;
static int dummy_message;

static void log_line(const char *format, const char *value) {
    const char *path = getenv("KAP_FAKE_GST_LOG");
    FILE *file;
    if (!path) return;
    file = fopen(path, "a");
    if (!file) return;
    fprintf(file, format, value ? value : "");
    fputc('\n', file);
    fclose(file);
}

void gst_init(int *argc, char ***argv) { (void)argc; (void)argv; }

void *gst_element_factory_make(const char *factory, const char *name) {
    (void)name;
    log_line("factory=%s", factory);
    if (!factory) return NULL;
    if (strcmp(factory, "playbin2") == 0 || strcmp(factory, "playbin") == 0) {
        return &dummy_playbin;
    }
    if (strcmp(factory, "mixersink") == 0) return &dummy_sink;
    return NULL;
}

int gst_element_set_state(void *element, int state) {
    char value[32];
    (void)element;
    snprintf(value, sizeof(value), "%d", state);
    log_line("state=%s", value);
    return 1;
}

void *gst_element_get_bus(void *element) {
    (void)element;
    return &dummy_bus;
}

void *gst_bus_poll(void *bus, unsigned int types, int64_t timeout) {
    (void)bus;
    (void)timeout;
    if (types == GST_MESSAGE_ERROR) {
        log_line("poll=%s", "error-empty");
        return NULL;
    }
    if (types == GST_MESSAGE_EOS) {
        log_line("poll=%s", "eos");
        return &dummy_message;
    }
    log_line("poll=%s", "unknown");
    return NULL;
}

void gst_message_parse_error(void *message, void **error, char **debug) {
    (void)message;
    if (error) *error = NULL;
    if (debug) *debug = NULL;
}

void gst_object_unref(void *object) { (void)object; }
void gst_mini_object_unref(void *object) { (void)object; }
