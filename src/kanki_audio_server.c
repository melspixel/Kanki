#define _POSIX_C_SOURCE 200809L
#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <limits.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

#define MA_NO_DEVICE_IO
#define MA_NO_ENCODING
#define MA_NO_GENERATION
#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#define PORT 17392
#define REQ_MAX 8192
#define PATH_MAX_LOCAL 4096

static volatile sig_atomic_t running = 1;
static pid_t player_pid = -1;

static void stop_player(void)
{
    if (player_pid > 0) {
        /* The decoder spawns /bin/sh -> gst-launch. Put the playback tree in
         * its own process group so stop/new-card cannot leave an orphaned
         * mixersink pipeline playing behind the next pronunciation. */
        kill(-player_pid, SIGTERM);
        waitpid(player_pid, NULL, 0);
        player_pid = -1;
    }
}

static void on_signal(int sig)
{
    (void)sig;
    running = 0;
    if (player_pid > 0) kill(-player_pid, SIGTERM);
}

static int hexval(char c)
{
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

static void url_decode(char *dst, size_t cap, const char *src)
{
    size_t di = 0;
    while (*src && di + 1 < cap) {
        if (src[0] == '%' && src[1] && src[2]) {
            int hi = hexval(src[1]), lo = hexval(src[2]);
            if (hi >= 0 && lo >= 0) {
                dst[di++] = (char)((hi << 4) | lo);
                src += 3;
                continue;
            }
        }
        dst[di++] = (*src == '+') ? ' ' : *src;
        src++;
    }
    dst[di] = '\0';
}

static int has_parent_ref(const char *s)
{
    return strstr(s, "../") || strstr(s, "/..") || strcmp(s, "..") == 0;
}

static int resolve_media_path(const char *src, char *out, size_t out_cap)
{
    const char *media = getenv("KANKI_MEDIA_DIR");
    const char *p = src;
    size_t media_len;

    if (!media || !*media || !src || !*src) return 0;
    media_len = strlen(media);

    if (strncmp(p, "file://", 7) == 0) p += 7;
    if (strncmp(p, "localhost/", 10) == 0) p += 10;

    if (p[0] == '/') {
        if (strncmp(p, media, media_len) != 0 || (p[media_len] != '/' && p[media_len] != '\0')) return 0;
        if (strlen(p) + 1 > out_cap) return 0;
        strcpy(out, p);
    } else {
        while (*p == '/' || (p[0] == '.' && p[1] == '/')) {
            if (*p == '/') p++;
            else p += 2;
        }
        if (has_parent_ref(p)) return 0;
        if (snprintf(out, out_cap, "%s/%s", media, p) >= (int)out_cap) return 0;
    }

    {
        char *q = strchr(out, '?'); if (q) *q = '\0';
        q = strchr(out, '#'); if (q) *q = '\0';
    }
    return access(out, R_OK) == 0;
}

static int decode_to_gst(const char *path)
{
    ma_decoder decoder;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 2, 44100);
    /* Kindle's validated third-party Bluetooth path is GStreamer 0.10 fdsrc
     * -> Amazon mixersink with stream-type=Music.  The stream type matters:
     * audiomgrd uses it to claim the music/A2DP route. */
    const char *gst_cmd =
        "GST=/usr/bin/gst-launch-0.10; [ -x \"$GST\" ] || GST=/usr/bin/gst-launch; "
        "\"$GST\" -v fdsrc fd=0 "
        "! 'audio/x-raw-int,endianness=(int)1234,signed=(boolean)true,width=(int)16,depth=(int)16,rate=(int)44100,channels=(int)2' "
        "! queue ! mixersink stream-type=Music";
    FILE *gst;
    ma_int16 pcm[4096 * 2];
    int status;

    fprintf(stderr, "kanki-audio: decode/play %s\n", path);
    fflush(stderr);

    if (ma_decoder_init_file(path, &cfg, &decoder) != MA_SUCCESS) {
        fprintf(stderr, "kanki-audio: decoder could not open media\n");
        return 2;
    }
    gst = popen(gst_cmd, "w");
    if (!gst) {
        fprintf(stderr, "kanki-audio: popen(gst-launch) failed: %s\n", strerror(errno));
        ma_decoder_uninit(&decoder);
        return 3;
    }

    while (1) {
        ma_uint64 frames = 0;
        ma_result r = ma_decoder_read_pcm_frames(&decoder, pcm, 4096, &frames);
        if (frames > 0) {
            if (fwrite(pcm, sizeof(ma_int16) * 2, (size_t)frames, gst) != (size_t)frames) {
                fprintf(stderr, "kanki-audio: gst pipe closed early\n");
                break;
            }
        }
        if (r == MA_AT_END || frames == 0) break;
        if (r != MA_SUCCESS) {
            fprintf(stderr, "kanki-audio: decode error %d\n", (int)r);
            break;
        }
    }

    ma_decoder_uninit(&decoder);
    status = pclose(gst);
    fprintf(stderr, "kanki-audio: gst exit status=%d\n", status);
    fflush(stderr);
    return status == 0 ? 0 : 4;
}

static void start_player(const char *path)
{
    pid_t pid;
    stop_player();
    pid = fork();
    if (pid == 0) {
        setpgid(0, 0);
        signal(SIGTERM, SIG_DFL);
        _exit(decode_to_gst(path));
    }
    if (pid > 0) {
        /* Close the fork/setpgid race from the parent side as well. */
        setpgid(pid, pid);
        player_pid = pid;
    }
}

static void reap_player(void)
{
    if (player_pid > 0) {
        pid_t r = waitpid(player_pid, NULL, WNOHANG);
        if (r == player_pid) player_pid = -1;
    }
}

static void http_reply(int fd, int code, const char *body)
{
    char buf[512];
    const char *status = code == 200 ? "OK" : (code == 404 ? "Not Found" : "Bad Request");
    int n = snprintf(buf, sizeof(buf),
        "HTTP/1.1 %d %s\r\nContent-Type: text/plain\r\nCache-Control: no-store\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\nContent-Length: %lu\r\n\r\n%s",
        code, status, (unsigned long)strlen(body), body);
    if (n > 0) (void)write(fd, buf, (size_t)n);
}

static void handle_client(int fd)
{
    char req[REQ_MAX];
    char method[16], target[REQ_MAX];
    ssize_t n = read(fd, req, sizeof(req) - 1);
    if (n <= 0) return;
    req[n] = '\0';

    if (sscanf(req, "%15s %8191s", method, target) != 2 || strcmp(method, "GET") != 0) {
        http_reply(fd, 400, "bad request");
        return;
    }

    if (strncmp(target, "/stop", 5) == 0) {
        fprintf(stderr, "kanki-audio: stop\n");
        stop_player();
        http_reply(fd, 200, "stopped");
        return;
    }

    if (strncmp(target, "/play?", 6) == 0) {
        char *src_arg = strstr(target + 6, "src=");
        char decoded[PATH_MAX_LOCAL];
        char path[PATH_MAX_LOCAL];
        if (!src_arg) {
            http_reply(fd, 400, "missing src");
            return;
        }
        src_arg += 4;
        {
            char *amp = strchr(src_arg, '&');
            if (amp) *amp = '\0';
        }
        url_decode(decoded, sizeof(decoded), src_arg);
        fprintf(stderr, "kanki-audio: request src=%s\n", decoded);
        if (!resolve_media_path(decoded, path, sizeof(path))) {
            fprintf(stderr, "kanki-audio: media not found under %s\n", getenv("KANKI_MEDIA_DIR") ? getenv("KANKI_MEDIA_DIR") : "(unset)");
            http_reply(fd, 404, "media not found");
            return;
        }
        start_player(path);
        http_reply(fd, 200, "playing");
        return;
    }

    http_reply(fd, 404, "not found");
}

int main(void)
{
    int server_fd, one = 1;
    struct sockaddr_in addr;

    signal(SIGINT, on_signal);
    signal(SIGTERM, on_signal);
    signal(SIGPIPE, SIG_IGN);

    fprintf(stderr, "kanki-audio: starting, media=%s\n", getenv("KANKI_MEDIA_DIR") ? getenv("KANKI_MEDIA_DIR") : "(unset)");
    fflush(stderr);

    server_fd = socket(AF_INET, SOCK_STREAM, 0);
    if (server_fd < 0) return 1;
    setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    addr.sin_port = htons(PORT);

    if (bind(server_fd, (struct sockaddr *)&addr, sizeof(addr)) != 0 || listen(server_fd, 8) != 0) {
        fprintf(stderr, "kanki-audio: bind/listen failed: %s\n", strerror(errno));
        close(server_fd);
        return 2;
    }

    while (running) {
        int client = accept(server_fd, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        handle_client(client);
        close(client);
        reap_player();
    }

    close(server_fd);
    stop_player();
    return 0;
}
