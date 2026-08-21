#define _POSIX_C_SOURCE 200809L

#include "kanki_tts_player.h"

#include <dlfcn.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define GST_STATE_NULL 1
#define GST_STATE_PLAYING 4
#define GST_STATE_CHANGE_FAILURE 0
#define GST_MESSAGE_EOS (1u << 0)
#define GST_MESSAGE_ERROR (1u << 1)
#define KANKI_TTS_POLL_NS ((int64_t)100000000)

static const char KANKI_TTS_PIPELINE[] =
    "ttssrc name=kanki_tts ! "
    "audio/x-raw,format=(string)S16LE,layout=(string)interleaved,"
    "rate=(int)24000,channels=(int)1 ! "
    "mixersink stream-type=Music sync=true";

typedef void (*FnGstInit)(int *, char ***);
typedef void *(*FnGstParseLaunch)(const char *, void **);
typedef void *(*FnGstBinGetByName)(void *, const char *);
typedef int (*FnGstElementSetState)(void *, int);
typedef void *(*FnGstElementGetBus)(void *);
typedef void *(*FnGstBusPoll)(void *, unsigned int, int64_t);
typedef void (*FnGstMessageParseError)(void *, void **, char **);
typedef void (*FnGstObjectUnref)(void *);
typedef void (*FnGstMiniObjectUnref)(void *);
typedef void (*FnGObjectSet)(void *, const char *, ...);

struct tts_api {
    void *gstreamer;
    void *gobject;
    FnGstInit gst_init;
    FnGstParseLaunch gst_parse_launch;
    FnGstBinGetByName gst_bin_get_by_name;
    FnGstElementSetState gst_element_set_state;
    FnGstElementGetBus gst_element_get_bus;
    FnGstBusPoll gst_bus_poll;
    FnGstMessageParseError gst_message_parse_error;
    FnGstObjectUnref gst_object_unref;
    FnGstMiniObjectUnref gst_mini_object_unref;
    FnGObjectSet g_object_set;
};

static void *open_runtime(const char *override_name,
                          const char *const *names,
                          const char *label) {
    size_t index;
    void *handle;
    if (override_name && *override_name) {
        handle = dlopen(override_name, RTLD_NOW | RTLD_GLOBAL);
        if (!handle) {
            fprintf(stderr,
                    "audio: cannot load %s %s: %s\n",
                    label,
                    override_name,
                    dlerror());
        }
        return handle;
    }
    for (index = 0; names[index]; index += 1) {
        handle = dlopen(names[index], RTLD_NOW | RTLD_GLOBAL);
        if (handle) return handle;
    }
    fprintf(stderr, "audio: cannot load %s runtime: %s\n", label, dlerror());
    return NULL;
}

static int load_symbol(void *handle, const char *name, void **slot) {
    *slot = dlsym(handle, name);
    if (!*slot) {
        fprintf(stderr, "audio: missing TTS runtime symbol %s: %s\n", name, dlerror());
        return 0;
    }
    return 1;
}

#define LOAD(handle, api, member)                                                        \
    do {                                                                                  \
        if (!load_symbol((handle), #member, (void **)&((api)->member))) return 0;          \
    } while (0)

static int load_api(struct tts_api *api) {
    static const char *const gstreamer_names[] = {
        "libgstreamer-1.0.so.0",
        "libgstreamer-1.0.so",
        "/usr/lib/libgstreamer-1.0.so.0",
        "/usr/lib/libgstreamer-1.0.so",
        NULL,
    };
    static const char *const gobject_names[] = {
        "libgobject-2.0.so.0",
        "libgobject-2.0.so",
        "/usr/lib/libgobject-2.0.so.0",
        "/usr/lib/libgobject-2.0.so",
        NULL,
    };
    memset(api, 0, sizeof(*api));
    api->gstreamer = open_runtime(getenv("KANKI_GSTREAMER_LIBRARY"),
                                  gstreamer_names,
                                  "GStreamer");
    api->gobject = open_runtime(getenv("KANKI_GOBJECT_LIBRARY"), gobject_names, "GObject");
    if (!api->gstreamer || !api->gobject) return 0;
    LOAD(api->gstreamer, api, gst_init);
    LOAD(api->gstreamer, api, gst_parse_launch);
    LOAD(api->gstreamer, api, gst_bin_get_by_name);
    LOAD(api->gstreamer, api, gst_element_set_state);
    LOAD(api->gstreamer, api, gst_element_get_bus);
    LOAD(api->gstreamer, api, gst_bus_poll);
    LOAD(api->gstreamer, api, gst_message_parse_error);
    LOAD(api->gstreamer, api, gst_object_unref);
    api->gst_mini_object_unref =
        (FnGstMiniObjectUnref)dlsym(api->gstreamer, "gst_mini_object_unref");
    LOAD(api->gobject, api, g_object_set);
    return 1;
}

static void unload_api(struct tts_api *api) {
    if (api->gobject) dlclose(api->gobject);
    if (api->gstreamer) dlclose(api->gstreamer);
    memset(api, 0, sizeof(*api));
}

static void preload_ivona(void) {
    static int attempted = 0;
    static const char *const names[] = {
        "/usr/lib/tts/libIvonaEInkAPI.so.1.0",
        "/usr/lib/tts/libIvonaEInkCommon.so.1.0",
        NULL,
    };
    size_t index;
    if (attempted || getenv("KANKI_TTS_SKIP_IVONA_PRELOAD")) return;
    attempted = 1;
    for (index = 0; names[index]; index += 1) {
        if (!dlopen(names[index], RTLD_LAZY | RTLD_GLOBAL)) {
            fprintf(stderr,
                    "audio: optional TTS preload failed for %s: %s\n",
                    names[index],
                    dlerror());
        }
    }
}

static void *create_pipeline(struct tts_api *api, void **source) {
    int argc = 0;
    char **argv = NULL;
    void *error = NULL;
    void *pipeline;
    api->gst_init(&argc, &argv);
    pipeline = api->gst_parse_launch(KANKI_TTS_PIPELINE, &error);
    if (!pipeline) {
        fprintf(stderr, "audio: PW6 ttssrc/mixersink pipeline creation failed\n");
        return NULL;
    }
    *source = api->gst_bin_get_by_name(pipeline, "kanki_tts");
    if (!*source) {
        fprintf(stderr, "audio: PW6 ttssrc element lookup failed\n");
        api->gst_object_unref(pipeline);
        return NULL;
    }
    return pipeline;
}

int kanki_tts_runtime_probe(void) {
    struct tts_api api;
    void *pipeline = NULL;
    void *source = NULL;
    int result = 1;
    preload_ivona();
    if (!load_api(&api)) return 2;
    pipeline = create_pipeline(&api, &source);
    if (pipeline) result = 0;
    if (source) api.gst_object_unref(source);
    if (pipeline) api.gst_object_unref(pipeline);
    unload_api(&api);
    return result;
}

int kanki_tts_play(const char *text,
                   const char *language,
                   const char *voices,
                   const char *speed) {
    struct tts_api api;
    void *pipeline = NULL;
    void *source = NULL;
    void *bus = NULL;
    void *message = NULL;
    char *end = NULL;
    double speed_value;
    int result = 0;
    (void)voices;
    if (!text || !*text) return 50;
    if (speed && *speed) {
        speed_value = strtod(speed, &end);
        if (!end || *end != '\0') return 51;
    } else {
        speed_value = 1.0;
    }
    if (!isfinite(speed_value) || speed_value < 0.26 || speed_value > 10.0) return 51;

    preload_ivona();
    if (!load_api(&api)) return 52;
    pipeline = create_pipeline(&api, &source);
    if (!pipeline) {
        result = 53;
        goto cleanup;
    }
    if (language && *language) {
        api.g_object_set(source,
                         "textsource", text,
                         "voicelang", language,
                         "speed", speed_value,
                         (char *)NULL);
    } else {
        api.g_object_set(source,
                         "textsource", text,
                         "speed", speed_value,
                         (char *)NULL);
    }
    if (api.gst_element_set_state(pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        result = 54;
        goto cleanup;
    }
    bus = api.gst_element_get_bus(pipeline);
    if (!bus) {
        result = 55;
        goto cleanup;
    }
    for (;;) {
        message = api.gst_bus_poll(bus, GST_MESSAGE_ERROR, 0);
        if (message) {
            void *error = NULL;
            char *debug = NULL;
            api.gst_message_parse_error(message, &error, &debug);
            fprintf(stderr, "audio: PW6 TTS pipeline reported an error\n");
            if (api.gst_mini_object_unref) api.gst_mini_object_unref(message);
            message = NULL;
            result = 56;
            break;
        }
        message = api.gst_bus_poll(bus, GST_MESSAGE_EOS, KANKI_TTS_POLL_NS);
        if (!message) continue;
        if (api.gst_mini_object_unref) api.gst_mini_object_unref(message);
        message = NULL;
        break;
    }

cleanup:
    if (pipeline) (void)api.gst_element_set_state(pipeline, GST_STATE_NULL);
    if (message && api.gst_mini_object_unref) api.gst_mini_object_unref(message);
    if (bus) api.gst_object_unref(bus);
    if (source) api.gst_object_unref(source);
    if (pipeline) api.gst_object_unref(pipeline);
    unload_api(&api);
    return result;
}
