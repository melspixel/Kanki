#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#include "kanki_audio_protocol.h"
#include "kanki_tts_player.h"

#define MA_NO_DEVICE_IO
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MA_NO_THREADING
#define MA_NO_RESOURCE_MANAGER
#define MA_NO_NODE_GRAPH
#define MA_NO_ENGINE
#define MA_NO_RUNTIME_LINKING
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#define AUDIO_PORT 17392
#define REQUEST_CAPACITY 16384
#define PATH_CAPACITY 4096

static volatile sig_atomic_t keep_running = 1;
static pid_t active_job = -1;
static unsigned long job_sequence = 0;

static void stop_active_job(void) {
    if (active_job > 0) {
        (void)kill(-active_job, SIGTERM);
        (void)waitpid(active_job, NULL, 0);
        active_job = -1;
    }
}

static void on_signal(int signal_number) {
    (void)signal_number;
    keep_running = 0;
    if (active_job > 0) (void)kill(-active_job, SIGTERM);
}

static int is_remote(const char *source) {
    return source &&
           (strncmp(source, "https://", 8) == 0 || strncmp(source, "http://", 7) == 0);
}

static int resolve_local_media(const char *source, char *resolved, size_t capacity) {
    const char *media_directory = getenv("KANKI_MEDIA_DIR");
    const char *relative = source;
    char candidate[PATH_CAPACITY];
    char media_real[PATH_CAPACITY];
    char candidate_real[PATH_CAPACITY];
    size_t prefix_length;

    if (!media_directory || !*media_directory || !source || !*source) return 0;
    if (strncmp(relative, "file://", 7) == 0) relative += 7;
    if (strstr(relative, "../") || strstr(relative, "/..") || strcmp(relative, "..") == 0) return 0;

    if (*relative == '/') {
        if (snprintf(candidate, sizeof(candidate), "%s", relative) >= (int)sizeof(candidate)) return 0;
    } else {
        while (relative[0] == '.' && relative[1] == '/') relative += 2;
        if (snprintf(candidate, sizeof(candidate), "%s/%s", media_directory, relative) >=
            (int)sizeof(candidate)) return 0;
    }
    {
        char *suffix = strpbrk(candidate, "?#");
        if (suffix) *suffix = '\0';
    }
    if (!realpath(media_directory, media_real) || !realpath(candidate, candidate_real)) return 0;
    prefix_length = strlen(media_real);
    if (strncmp(candidate_real, media_real, prefix_length) != 0 ||
        (candidate_real[prefix_length] != '/' && candidate_real[prefix_length] != '\0')) return 0;
    if (strlen(candidate_real) + 1 > capacity) return 0;
    memcpy(resolved, candidate_real, strlen(candidate_real) + 1);
    return 1;
}

static void write_u16le(unsigned char *output, uint16_t value) {
    output[0] = (unsigned char)(value & 0xffu);
    output[1] = (unsigned char)((value >> 8) & 0xffu);
}

static void write_u32le(unsigned char *output, uint32_t value) {
    output[0] = (unsigned char)(value & 0xffu);
    output[1] = (unsigned char)((value >> 8) & 0xffu);
    output[2] = (unsigned char)((value >> 16) & 0xffu);
    output[3] = (unsigned char)((value >> 24) & 0xffu);
}

static int decode_to_wav(const char *input_path, const char *output_path) {
    ma_decoder decoder;
    ma_decoder_config configuration = ma_decoder_config_init(ma_format_s16, 2, 44100);
    ma_int16 frames[4096 * 2];
    uint64_t total_frames = 0;
    FILE *output;
    unsigned char header[44];

    if (ma_decoder_init_file(input_path, &configuration, &decoder) != MA_SUCCESS) {
        fprintf(stderr, "audio: decoder could not open %s\n", input_path);
        return 2;
    }
    output = fopen(output_path, "wb+");
    if (!output) {
        fprintf(stderr, "audio: cannot create %s: %s\n", output_path, strerror(errno));
        ma_decoder_uninit(&decoder);
        return 3;
    }

    memset(header, 0, sizeof(header));
    memcpy(header, "RIFF", 4);
    memcpy(header + 8, "WAVEfmt ", 8);
    write_u32le(header + 16, 16);
    write_u16le(header + 20, 1);
    write_u16le(header + 22, 2);
    write_u32le(header + 24, 44100);
    write_u32le(header + 28, 44100 * 4);
    write_u16le(header + 32, 4);
    write_u16le(header + 34, 16);
    memcpy(header + 36, "data", 4);
    if (fwrite(header, 1, sizeof(header), output) != sizeof(header)) {
        fclose(output);
        unlink(output_path);
        ma_decoder_uninit(&decoder);
        return 4;
    }

    for (;;) {
        ma_uint64 frame_count = 0;
        ma_result result = ma_decoder_read_pcm_frames(&decoder, frames, 4096, &frame_count);
        if (frame_count > 0) {
            if (fwrite(frames, sizeof(ma_int16) * 2, (size_t)frame_count, output) !=
                (size_t)frame_count) {
                fclose(output);
                unlink(output_path);
                ma_decoder_uninit(&decoder);
                return 5;
            }
            total_frames += frame_count;
        }
        if (result == MA_AT_END || frame_count == 0) break;
        if (result != MA_SUCCESS) {
            fclose(output);
            unlink(output_path);
            ma_decoder_uninit(&decoder);
            return 6;
        }
    }

    {
        uint64_t byte_count_64 = total_frames * 4;
        uint32_t byte_count = byte_count_64 > UINT32_MAX ? UINT32_MAX : (uint32_t)byte_count_64;
        write_u32le(header + 4, 36u + byte_count);
        write_u32le(header + 40, byte_count);
        (void)fseek(output, 0, SEEK_SET);
        (void)fwrite(header, 1, sizeof(header), output);
    }
    fclose(output);
    ma_decoder_uninit(&decoder);
    return total_frames > 0 ? 0 : 7;
}

static void request_music_focus(void) {
    pid_t child = fork();
    int status;
    if (child == 0) {
        execl("/usr/bin/lipc-set-prop", "lipc-set-prop",
              "com.lab126.audiomgrd", "setFocus", "Music", (char *)NULL);
        _exit(127);
    }
    if (child > 0) (void)waitpid(child, &status, 0);
}

static int run_player(const char *first_argument, const char *second_argument) {
    const char *player = getenv("KANKI_GST_PLAYER");
    const char *loader = getenv("KANKI_GST_LOADER");
    pid_t child;
    int status = 0;
    if (!player || !*player) return 20;
    request_music_focus();
    child = fork();
    if (child == 0) {
        if (loader && *loader) {
            if (second_argument) execl(loader, loader, player, first_argument, second_argument, (char *)NULL);
            else execl(loader, loader, player, first_argument, (char *)NULL);
        }
        if (second_argument) execl(player, player, first_argument, second_argument, (char *)NULL);
        else execl(player, player, first_argument, (char *)NULL);
        _exit(127);
    }
    if (child < 0) return 21;
    if (waitpid(child, &status, 0) < 0) return 22;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 23;
}

static int download_remote(const char *url, const char *output_path) {
    pid_t child = fork();
    int status = 0;
    struct stat information;
    if (child == 0) {
        execl("/usr/bin/curl", "curl", "-L", "--fail", "--silent", "--show-error",
              "-o", output_path, url, (char *)NULL);
        execl("/usr/bin/wget", "wget", "-q", "-O", output_path, url, (char *)NULL);
        execl("/bin/busybox", "busybox", "wget", "-q", "-O", output_path, url,
              (char *)NULL);
        _exit(127);
    }
    if (child < 0 || waitpid(child, &status, 0) < 0) return 30;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0 || stat(output_path, &information) != 0 ||
        information.st_size <= 0) {
        unlink(output_path);
        return 31;
    }
    return 0;
}

static int play_source(const char *source) {
    char input_path[PATH_CAPACITY];
    char downloaded_path[PATH_CAPACITY];
    char wav_path[PATH_CAPACITY];
    int downloaded = 0;
    int result;
    if (is_remote(source)) {
        if (snprintf(downloaded_path, sizeof(downloaded_path), "/tmp/kanki-download-%ld-%lu",
                     (long)getpid(), ++job_sequence) >= (int)sizeof(downloaded_path)) return 40;
        result = download_remote(source, downloaded_path);
        if (result != 0) return result;
        memcpy(input_path, downloaded_path, strlen(downloaded_path) + 1);
        downloaded = 1;
    } else if (!resolve_local_media(source, input_path, sizeof(input_path))) {
        return 41;
    }
    if (snprintf(wav_path, sizeof(wav_path), "/tmp/kanki-audio-%ld-%lu.wav",
                 (long)getpid(), ++job_sequence) >= (int)sizeof(wav_path)) {
        if (downloaded) unlink(downloaded_path);
        return 42;
    }
    result = decode_to_wav(input_path, wav_path);
    if (result == 0) result = run_player(wav_path, NULL);
    unlink(wav_path);
    if (downloaded) unlink(downloaded_path);
    return result;
}

static int play_tts(const struct kanki_audio_item *item) {
    if (!item || !item->value[0]) return 50;
    request_music_focus();
    return kanki_tts_play(item->value, item->language, item->voices, item->speed);
}

static void reap_active_job(void) {
    if (active_job > 0 && waitpid(active_job, NULL, WNOHANG) == active_job) active_job = -1;
}

static int start_job(const struct kanki_audio_item *item) {
    pid_t child;
    if (!item || !item->value[0]) return 0;
    stop_active_job();
    child = fork();
    if (child == 0) {
        (void)setpgid(0, 0);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        _exit(item->kind == KANKI_AUDIO_ITEM_TTS ? play_tts(item) : play_source(item->value));
    }
    if (child < 0) return 0;
    (void)setpgid(child, child);
    active_job = child;
    return 1;
}

static int start_sequence_job(
    const struct kanki_audio_item items[KANKI_AUDIO_MAX_SEQUENCE_ITEMS],
    size_t count) {
    pid_t pid;
    size_t i;
    stop_active_job();
    pid = fork();
    if (pid == 0) {
        int result = 0;
        (void)setpgid(0, 0);
        signal(SIGTERM, SIG_DFL);
        signal(SIGINT, SIG_DFL);
        for (i = 0; i < count; i += 1) {
            result = items[i].kind == KANKI_AUDIO_ITEM_TTS ? play_tts(&items[i])
                                                           : play_source(items[i].value);
            if (result != 0) break;
        }
        _exit(result >= 0 && result <= 255 ? result : 1);
    }
    if (pid < 0) return 0;
    (void)setpgid(pid, pid);
    active_job = pid;
    return 1;
}

static void reply_http(int descriptor, int status_code, const char *message) {
    char response[768];
    const char *status = status_code == 200 ? "OK" :
                         (status_code == 404 ? "Not Found" : "Bad Request");
    int length = snprintf(response, sizeof(response),
                          "HTTP/1.1 %d %s\r\n"
                          "Content-Type: text/plain; charset=utf-8\r\n"
                          "Cache-Control: no-store\r\n"
                          "Access-Control-Allow-Origin: *\r\n"
                          "Connection: close\r\n"
                          "Content-Length: %lu\r\n\r\n%s",
                          status_code, status, (unsigned long)strlen(message), message);
    if (length > 0) (void)write(descriptor, response, (size_t)length);
}

static void handle_client(int descriptor) {
    char request[REQUEST_CAPACITY];
    char method[16];
    char target[REQUEST_CAPACITY];
    struct kanki_audio_item item;
    struct kanki_audio_item sequence[KANKI_AUDIO_MAX_SEQUENCE_ITEMS];
    size_t sequence_count = 0;
    ssize_t length = read(descriptor, request, sizeof(request) - 1);
    if (length <= 0) return;
    request[length] = '\0';
    if (sscanf(request, "%15s %16383s", method, target) != 2 || strcmp(method, "GET") != 0) {
        reply_http(descriptor, 400, "bad request");
        return;
    }
    if (strncmp(target, "/stop", 5) == 0) {
        stop_active_job();
        reply_http(descriptor, 200, "stopped");
    } else if (strncmp(target, "/sequence?", 10) == 0) {
        if (!kanki_audio_parse_sequence(target, sequence, &sequence_count)) {
            reply_http(descriptor, 400, "invalid sequence");
        } else if (!start_sequence_job(sequence, sequence_count)) {
            reply_http(descriptor, 400, "unable to start sequence");
        } else {
            reply_http(descriptor, 200, "playing sequence");
        }
    } else if (strncmp(target, "/play?", 6) == 0) {
        memset(&item, 0, sizeof(item));
        item.kind = KANKI_AUDIO_ITEM_SOUND;
        if (!kanki_audio_query_value(target, "src", item.value, sizeof(item.value)) ||
            !item.value[0]) {
            reply_http(descriptor, 400, "missing src");
        } else if (!start_job(&item)) {
            reply_http(descriptor, 400, "unable to start playback");
        } else {
            reply_http(descriptor, 200, "playing");
        }
    } else if (strncmp(target, "/tts?", 5) == 0) {
        if (!kanki_audio_parse_tts_request(target, &item)) {
            reply_http(descriptor, 400, "invalid tts request");
        } else if (!start_job(&item)) {
            reply_http(descriptor, 400, "unable to start tts");
        } else {
            reply_http(descriptor, 200, "speaking");
        }
    } else if (strncmp(target, "/health", 7) == 0) {
        reply_http(descriptor, 200, "ok");
    } else {
        reply_http(descriptor, 404, "not found");
    }
}

int main(int argc, char **argv) {
    int server_descriptor;
    int enabled = 1;
    struct sockaddr_in address;

    if (argc == 2 && strcmp(argv[1], "--tts-runtime-probe") == 0) {
        int result = kanki_tts_runtime_probe();
        if (result == 0) puts("kanki-tts-runtime=pass");
        return result;
    }
    if (argc != 1) {
        fprintf(stderr, "usage: %s [--tts-runtime-probe]\n", argv[0]);
        return 64;
    }

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);
    server_descriptor = socket(AF_INET, SOCK_STREAM, 0);
    if (server_descriptor < 0) return 1;
    (void)setsockopt(server_descriptor, SOL_SOCKET, SO_REUSEADDR, &enabled, sizeof(enabled));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons(AUDIO_PORT);
    if (bind(server_descriptor, (struct sockaddr *)&address, sizeof(address)) != 0 ||
        listen(server_descriptor, 8) != 0) {
        fprintf(stderr, "audio: bind/listen failed: %s\n", strerror(errno));
        close(server_descriptor);
        return 2;
    }
    fprintf(stderr, "audio: ready media=%s player=%s\n",
            getenv("KANKI_MEDIA_DIR") ? getenv("KANKI_MEDIA_DIR") : "(unset)",
            getenv("KANKI_GST_PLAYER") ? getenv("KANKI_GST_PLAYER") : "(unset)");
    fflush(stderr);

    while (keep_running) {
        int client_descriptor = accept(server_descriptor, NULL, NULL);
        if (client_descriptor < 0) {
            if (errno == EINTR) continue;
            break;
        }
        handle_client(client_descriptor);
        close(client_descriptor);
        reap_active_job();
    }
    close(server_descriptor);
    stop_active_job();
    return 0;
}
