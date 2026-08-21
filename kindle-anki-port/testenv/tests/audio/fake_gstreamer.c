#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int dummy_playbin;
static int dummy_sink;
static int dummy_bus;
static int dummy_message;

static void log_factory(const char *factory) {
    const char *path = getenv("KAP_FAKE_GST_LOG");
    FILE *file;
    if (!path) return;
    file = fopen(path, "a");
    if (!file) return;
    fprintf(file, "factory=%s\n", factory ? factory : "");
    fclose(file);
}

void gst_init(int *argc, char ***argv) { (void)argc; (void)argv; }
void *gst_element_factory_make(const char *factory, const char *name) {
    (void)name;
    log_factory(factory);
    if (!factory) return NULL;
    if (strcmp(factory, "playbin2") == 0 || strcmp(factory, "playbin") == 0) return &dummy_playbin;
    if (strcmp(factory, "mixersink") == 0) return &dummy_sink;
    return NULL;
}
int gst_element_set_state(void *element, int state) { (void)element; (void)state; return 1; }
void *gst_element_get_bus(void *element) { (void)element; return &dummy_bus; }
void *gst_bus_timed_pop_filtered(void *bus, uint64_t timeout, unsigned int types) {
    (void)bus;
    (void)timeout;
    (void)types;
    return &dummy_message;
}
void gst_message_unref(void *message) { (void)message; }
void gst_object_unref(void *object) { (void)object; }
