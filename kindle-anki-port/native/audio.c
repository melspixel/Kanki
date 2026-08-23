#define _XOPEN_SOURCE 700
#define _POSIX_C_SOURCE 200809L

#include <dlfcn.h>
#include <errno.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

/*
 * Kindle audio worker.
 *
 * Amazon routes application audio through GStreamer's `mixersink`.  The worker
 * binds GStreamer/GLib at runtime so the production binary uses the exact
 * firmware libraries and a fresh pipeline for every request.  Recreating the
 * pipeline is intentional: after Bluetooth settings change, the next request
 * must resolve the current Kindle audio route instead of retaining a stale
 * ALSA device.
 */

#define GST_STATE_NULL 1
#define GST_STATE_PLAYING 4
#define GST_STATE_CHANGE_FAILURE 0
#define GST_MESSAGE_EOS (1u << 0)
#define GST_MESSAGE_ERROR (1u << 1)
#define KAP_GST_POLL_NS ((int64_t)100000000)

struct KapGError {
    unsigned int domain;
    int code;
    char *message;
};

typedef void (*FnGstInit)(int *, char ***);
typedef void *(*FnGstElementFactoryMake)(const char *, const char *);
typedef int (*FnGstElementSetState)(void *, int);
typedef void *(*FnGstElementGetBus)(void *);
typedef void *(*FnGstBusPoll)(void *, unsigned int, int64_t);
typedef void (*FnGstMessageParseError)(void *, struct KapGError **, char **);
typedef void (*FnGstObjectUnref)(void *);
typedef void (*FnGstMiniObjectUnref)(void *);
typedef void (*FnGObjectSet)(void *, const char *, ...);
typedef void (*FnGErrorFree)(struct KapGError *);
typedef void (*FnGFree)(void *);

typedef struct {
    void *gst_lib;
    void *gobject_lib;
    void *glib_lib;
    const char *gst_runtime;
    FnGstInit gst_init;
    FnGstElementFactoryMake gst_element_factory_make;
    FnGstElementSetState gst_element_set_state;
    FnGstElementGetBus gst_element_get_bus;
    FnGstBusPoll gst_bus_poll;
    FnGstMessageParseError gst_message_parse_error;
    FnGstObjectUnref gst_object_unref;
    FnGstMiniObjectUnref gst_mini_object_unref;
    FnGObjectSet g_object_set;
    FnGErrorFree g_error_free;
    FnGFree g_free;
} AudioApi;

static volatile sig_atomic_t g_stop = 0;

static void on_signal(int signal_number) {
    (void)signal_number;
    g_stop = 1;
}

static void *open_first(const char *const *names, const char **selected) {
    size_t index;
    for (index = 0; names[index] != NULL; index += 1) {
        void *handle = dlopen(names[index], RTLD_NOW | RTLD_GLOBAL);
        if (handle != NULL) {
            if (selected != NULL) *selected = names[index];
            return handle;
        }
    }
    return NULL;
}

static int load_required(void *handle, const char *name, void **slot) {
    *slot = dlsym(handle, name);
    if (*slot == NULL) {
        fprintf(stderr, "missing runtime symbol %s: %s\n", name, dlerror());
        return 0;
    }
    return 1;
}

#define LOAD(handle, api, member) \
    do { \
        if (!load_required((handle), #member, (void **)&((api)->member))) return 0; \
    } while (0)

static int load_audio_api(AudioApi *api) {
    static const char *const gst_names[] = {
        "libgstreamer-0.10.so.0",
        "libgstreamer-0.10.so",
        "libgstreamer-1.0.so.0",
        "libgstreamer-1.0.so",
        NULL
    };
    static const char *const gobject_names[] = {
        "libgobject-2.0.so.0", "libgobject-2.0.so", NULL
    };
    static const char *const glib_names[] = {
        "libglib-2.0.so.0", "libglib-2.0.so", NULL
    };

    memset(api, 0, sizeof(*api));
    api->gst_lib = open_first(gst_names, &api->gst_runtime);
    api->gobject_lib = open_first(gobject_names, NULL);
    api->glib_lib = open_first(glib_names, NULL);
    if (api->gst_lib == NULL || api->gobject_lib == NULL || api->glib_lib == NULL) {
        fprintf(stderr, "unable to load Kindle GStreamer/GLib runtime: %s\n", dlerror());
        return 0;
    }

    LOAD(api->gst_lib, api, gst_init);
    LOAD(api->gst_lib, api, gst_element_factory_make);
    LOAD(api->gst_lib, api, gst_element_set_state);
    LOAD(api->gst_lib, api, gst_element_get_bus);
    LOAD(api->gst_lib, api, gst_bus_poll);
    LOAD(api->gst_lib, api, gst_message_parse_error);
    LOAD(api->gst_lib, api, gst_object_unref);
    api->gst_mini_object_unref = (FnGstMiniObjectUnref)
        dlsym(api->gst_lib, "gst_mini_object_unref");
    LOAD(api->gobject_lib, api, g_object_set);
    LOAD(api->glib_lib, api, g_error_free);
    LOAD(api->glib_lib, api, g_free);
    return 1;
}

static void unload_audio_api(AudioApi *api) {
    if (api->gst_lib != NULL) dlclose(api->gst_lib);
    if (api->gobject_lib != NULL) dlclose(api->gobject_lib);
    if (api->glib_lib != NULL) dlclose(api->glib_lib);
    memset(api, 0, sizeof(*api));
}

static int is_uri_unreserved(unsigned char byte) {
    return (byte >= 'a' && byte <= 'z') ||
           (byte >= 'A' && byte <= 'Z') ||
           (byte >= '0' && byte <= '9') ||
           byte == '-' || byte == '_' || byte == '.' || byte == '~' || byte == '/';
}

static char *file_uri(const char *path) {
    static const char hex[] = "0123456789ABCDEF";
    char absolute[PATH_MAX];
    const unsigned char *cursor;
    char *uri;
    char *out;
    size_t needed = strlen("file://") + 1;

    if (path == NULL || *path == '\0') return NULL;
    if (path[0] == '/') {
        if (snprintf(absolute, sizeof(absolute), "%s", path) >= (int)sizeof(absolute)) {
            return NULL;
        }
    } else if (realpath(path, absolute) == NULL) {
        return NULL;
    }

    for (cursor = (const unsigned char *)absolute; *cursor != '\0'; cursor += 1) {
        needed += is_uri_unreserved(*cursor) ? 1u : 3u;
    }
    uri = malloc(needed);
    if (uri == NULL) return NULL;
    memcpy(uri, "file://", strlen("file://"));
    out = uri + strlen("file://");
    for (cursor = (const unsigned char *)absolute; *cursor != '\0'; cursor += 1) {
        if (is_uri_unreserved(*cursor)) {
            *out++ = (char)*cursor;
        } else {
            *out++ = '%';
            *out++ = hex[*cursor >> 4];
            *out++ = hex[*cursor & 0x0f];
        }
    }
    *out = '\0';
    return uri;
}

static int has_http_scheme(const char *source) {
    return source != NULL &&
           (strncmp(source, "https://", 8) == 0 || strncmp(source, "http://", 7) == 0);
}

static char *source_uri(const char *source) {
    if (has_http_scheme(source)) return strdup(source);
    if (source != NULL && strncmp(source, "file://", 7) == 0) return strdup(source);
    return file_uri(source);
}

static int play_source(const char *source) {
    AudioApi api;
    void *player = NULL;
    void *sink = NULL;
    void *bus = NULL;
    void *message = NULL;
    char *uri = NULL;
    int result = 0;
    int argc = 0;
    char **argv = NULL;

    if (!load_audio_api(&api)) return 2;
    api.gst_init(&argc, &argv);

    uri = source_uri(source);
    if (uri == NULL) {
        fprintf(stderr, "unable to convert source to URI: %s\n", source ? source : "(null)");
        result = 3;
        goto cleanup;
    }

    player = api.gst_element_factory_make("playbin2", "kap-player");
    if (player == NULL) player = api.gst_element_factory_make("playbin", "kap-player");
    if (player == NULL) {
        fprintf(stderr, "GStreamer playbin/playbin2 is unavailable\n");
        result = 4;
        goto cleanup;
    }

    /* `mixersink` is Amazon's policy-aware route.  A non-Kindle host may not
     * provide it; in that case playbin's default sink is retained so the same
     * binary remains testable in a generic GStreamer environment. */
    sink = api.gst_element_factory_make("mixersink", "kap-mixersink");
    api.g_object_set(player, "uri", uri, NULL);
    if (sink != NULL) api.g_object_set(player, "audio-sink", sink, NULL);

    if (api.gst_element_set_state(player, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
        fprintf(stderr, "GStreamer failed to enter PLAYING state for %s\n", uri);
        result = 5;
        goto cleanup;
    }

    bus = api.gst_element_get_bus(player);
    if (bus == NULL) {
        fprintf(stderr, "GStreamer player returned no bus\n");
        result = 6;
        goto cleanup;
    }

    while (!g_stop) {
        /* GstMessage is opaque at this ABI boundary. Poll ERROR and EOS
         * separately so an EOS message is never passed to parse_error(). */
        message = api.gst_bus_poll(bus, GST_MESSAGE_ERROR, 0);
        if (message != NULL) {
            struct KapGError *error = NULL;
            char *debug = NULL;
            api.gst_message_parse_error(message, &error, &debug);
            fprintf(stderr, "GStreamer playback error: %s\n",
                    error != NULL && error->message != NULL
                        ? error->message
                        : "unknown error");
            if (debug != NULL) fprintf(stderr, "GStreamer debug: %s\n", debug);
            if (error != NULL) api.g_error_free(error);
            if (debug != NULL) api.g_free(debug);
            result = 7;
            if (api.gst_mini_object_unref != NULL) api.gst_mini_object_unref(message);
            message = NULL;
            break;
        }

        message = api.gst_bus_poll(bus, GST_MESSAGE_EOS, KAP_GST_POLL_NS);
        if (message == NULL) continue;
        if (api.gst_mini_object_unref != NULL) api.gst_mini_object_unref(message);
        message = NULL;
        break;
    }

cleanup:
    if (player != NULL) (void)api.gst_element_set_state(player, GST_STATE_NULL);
    if (message != NULL && api.gst_mini_object_unref != NULL) {
        api.gst_mini_object_unref(message);
    }
    if (bus != NULL) api.gst_object_unref(bus);
    if (sink != NULL) api.gst_object_unref(sink);
    if (player != NULL) api.gst_object_unref(player);
    free(uri);
    unload_audio_api(&api);
    return result;
}

static int synthesize(const char *binary, const char *text, const char *lang,
                      const char *speed_factor, char *output, size_t output_size) {
    pid_t child;
    int status;
    double factor = speed_factor ? strtod(speed_factor, NULL) : 1.0;
    int words_per_minute;
    char speed[32];

    if (!(factor > 0.2 && factor < 4.0)) factor = 1.0;
    words_per_minute = (int)(175.0 * factor + 0.5);
    snprintf(speed, sizeof(speed), "%d", words_per_minute);
    if (snprintf(output, output_size, "/tmp/kap-tts-%ld.wav", (long)getpid()) >=
        (int)output_size) return 8;
    unlink(output);

    child = fork();
    if (child == 0) {
        execl(binary, binary, "-q", "-v", lang && *lang ? lang : "en",
              "-s", speed, "-w", output, text, (char *)NULL);
        _exit(127);
    }
    if (child < 0) {
        fprintf(stderr, "TTS fork failed: %s\n", strerror(errno));
        return 9;
    }
    if (waitpid(child, &status, 0) < 0 || !WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fprintf(stderr, "TTS synthesis failed\n");
        return 10;
    }
    return 0;
}

static int self_test(void) {
    char *uri = file_uri("/mnt/us/anki data/a b.mp3");
    int ok = uri != NULL &&
             strcmp(uri, "file:///mnt/us/anki%20data/a%20b.mp3") == 0 &&
             has_http_scheme("https://example.invalid/a.mp3") &&
             !has_http_scheme("ftp://example.invalid/a.mp3");
    if (!ok) {
        fprintf(stderr, "audio self-test failed: uri=%s\n", uri ? uri : "(null)");
        free(uri);
        return 1;
    }
    free(uri);
    puts("kap-audio self-test: ok");
    return 0;
}

int main(int argc, char **argv) {
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);

    if (argc == 2 && strcmp(argv[1], "--self-test") == 0) return self_test();
    if (argc == 3 && strcmp(argv[1], "--play") == 0) return play_source(argv[2]);
    if (argc == 6 && strcmp(argv[1], "--tts") == 0) {
        char temporary[128];
        int result = synthesize(argv[2], argv[3], argv[4], argv[5], temporary,
                                sizeof(temporary));
        if (result != 0) return result;
        result = play_source(temporary);
        unlink(temporary);
        return result;
    }
    fprintf(stderr, "usage: %s --play FILE_OR_URL | --tts ESPEAK TEXT LANG SPEED | --self-test\n",
            argv[0]);
    return 64;
}
