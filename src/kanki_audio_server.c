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

static int is_remote_url(const char *s)
{
    return s && (!strncmp(s, "http://", 7) || !strncmp(s, "https://", 8));
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

    if (!strncmp(p, "file://", 7)) p += 7;
    if (!strncmp(p, "localhost/", 10)) p += 10;
    if (is_remote_url(p)) return 0;

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

static void put16le(unsigned char *p, uint16_t v)
{
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
}

static void put32le(unsigned char *p, uint32_t v)
{
    p[0] = (unsigned char)(v & 0xff);
    p[1] = (unsigned char)((v >> 8) & 0xff);
    p[2] = (unsigned char)((v >> 16) & 0xff);
    p[3] = (unsigned char)((v >> 24) & 0xff);
}

static int decode_to_wav(const char *input, const char *output)
{
    ma_decoder decoder;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_s16, 2, 44100);
    ma_int16 pcm[4096 * 2];
    uint64_t frames_total = 0;
    FILE *f;
    unsigned char hdr[44];

    if (ma_decoder_init_file(input, &cfg, &decoder) != MA_SUCCESS) {
        fprintf(stderr, "kanki-audio: decoder could not open %s\n", input);
        return 2;
    }

    f = fopen(output, "wb+");
    if (!f) {
        fprintf(stderr, "kanki-audio: cannot create temp wav: %s\n", strerror(errno));
        ma_decoder_uninit(&decoder);
        return 3;
    }

    memset(hdr, 0, sizeof(hdr));
    memcpy(hdr, "RIFF", 4);
    memcpy(hdr + 8, "WAVEfmt ", 8);
    put32le(hdr + 16, 16);
    put16le(hdr + 20, 1);
    put16le(hdr + 22, 2);
    put32le(hdr + 24, 44100);
    put32le(hdr + 28, 44100 * 2 * 2);
    put16le(hdr + 32, 4);
    put16le(hdr + 34, 16);
    memcpy(hdr + 36, "data", 4);
    fwrite(hdr, 1, sizeof(hdr), f);

    while (1) {
        ma_uint64 frames = 0;
        ma_result r = ma_decoder_read_pcm_frames(&decoder, pcm, 4096, &frames);
        if (frames > 0) {
            if (fwrite(pcm, sizeof(ma_int16) * 2, (size_t)frames, f) != (size_t)frames) {
                fprintf(stderr, "kanki-audio: temp wav write failed\n");
                fclose(f);
                unlink(output);
                ma_decoder_uninit(&decoder);
                return 4;
            }
            frames_total += frames;
        }
        if (r == MA_AT_END || frames == 0) break;
        if (r != MA_SUCCESS) {
            fprintf(stderr, "kanki-audio: decode error %d\n", (int)r);
            break;
        }
    }

    {
        uint64_t data64 = frames_total * 4;
        uint32_t data_size = data64 > 0xffffffffu ? 0xffffffffu : (uint32_t)data64;
        put32le(hdr + 4, 36u + data_size);
        put32le(hdr + 40, data_size);
        fseek(f, 0, SEEK_SET);
        fwrite(hdr, 1, sizeof(hdr), f);
    }

    fclose(f);
    ma_decoder_uninit(&decoder);
    return 0;
}

static int launch_native_player(const char *wav_path)
{
    const char *player = getenv("KANKI_GST_PLAYER");
    const char *loader = getenv("KANKI_GST_LOADER");
    pid_t pid;
    int status = 0;

    if (!player || access(player, R_OK) != 0) {
        fprintf(stderr, "kanki-audio: native player missing/unreadable: %s (%s)\n",
            player ? player : "(unset)", strerror(errno));
        return 10;
    }

    pid = fork();
    if (pid == 0) {
        /* Files copied over MTP can lose the executable bit.  Running the ELF
         * through Kindle's system dynamic loader only requires the binary to be
         * readable and also keeps it on the device's native glibc ABI. */
        if (loader && access(loader, X_OK) == 0) {
            execl(loader, loader, player, wav_path, (char *)NULL);
            fprintf(stderr, "kanki-audio: loader exec failed: %s\n", strerror(errno));
        }
        execl(player, player, wav_path, (char *)NULL);
        fprintf(stderr, "kanki-audio: direct exec failed: %s\n", strerror(errno));
        _exit(127);
    }
    if (pid < 0) return 12;

    waitpid(pid, &status, 0);
    fprintf(stderr, "kanki-audio: native player status=%d\n", status);
    fflush(stderr);
    return (WIFEXITED(status) && WEXITSTATUS(status) == 0) ? 0 : 13;
}

static int decode_and_play(const char *path)
{
    char tmp[128];
    int rc;

    snprintf(tmp, sizeof(tmp), "/tmp/kanki-audio-%ld.wav", (long)getpid());
    fprintf(stderr, "kanki-audio: decode %s -> %s\n", path, tmp);
    rc = decode_to_wav(path, tmp);
    if (rc != 0) return 11;
    rc = launch_native_player(tmp);
    unlink(tmp);
    return rc;
}

static int download_remote(const char *url, const char *out)
{
    const char *tool = NULL;
    int kind = 0;
    pid_t pid;
    int status = 0;

    if (access("/usr/bin/curl", X_OK) == 0) { tool = "/usr/bin/curl"; kind = 1; }
    else if (access("/usr/bin/wget", X_OK) == 0) { tool = "/usr/bin/wget"; kind = 2; }
    else if (access("/bin/busybox", X_OK) == 0) { tool = "/bin/busybox"; kind = 3; }
    else {
        fprintf(stderr, "kanki-audio: no curl/wget/busybox downloader for remote audio\n");
        return 20;
    }

    fprintf(stderr, "kanki-audio: downloading %s via %s\n", url, tool);
    pid = fork();
    if (pid == 0) {
        if (kind == 1)
            execl(tool, tool, "-L", "--fail", "--silent", "--show-error", "-o", out, url, (char *)NULL);
        else if (kind == 2)
            execl(tool, tool, "-q", "-O", out, url, (char *)NULL);
        else
            execl(tool, tool, "wget", "-q", "-O", out, url, (char *)NULL);
        _exit(127);
    }
    if (pid < 0) return 21;
    waitpid(pid, &status, 0);
    if (!(WIFEXITED(status) && WEXITSTATUS(status) == 0) || access(out, R_OK) != 0) {
        fprintf(stderr, "kanki-audio: remote download failed status=%d\n", status);
        unlink(out);
        return 22;
    }
    return 0;
}

static int remote_and_play(const char *url)
{
    char tmp[128];
    int rc;
    snprintf(tmp, sizeof(tmp), "/tmp/kanki-remote-%ld.mp3", (long)getpid());
    rc = download_remote(url, tmp);
    if (rc == 0) rc = decode_and_play(tmp);
    unlink(tmp);
    return rc;
}

static void start_source(const char *src, int remote)
{
    pid_t pid;
    stop_player();
    pid = fork();
    if (pid == 0) {
        setpgid(0, 0);
        signal(SIGTERM, SIG_DFL);
        _exit(remote ? remote_and_play(src) : decode_and_play(src));
    }
    if (pid > 0) {
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
    char req[REQ_MAX], method[16], target[REQ_MAX];
    ssize_t n = read(fd, req, sizeof(req) - 1);
    if (n <= 0) return;
    req[n] = '\0';

    if (sscanf(req, "%15s %8191s", method, target) != 2 || strcmp(method, "GET")) {
        http_reply(fd, 400, "bad request");
        return;
    }

    if (!strncmp(target, "/stop", 5)) {
        fprintf(stderr, "kanki-audio: stop\n");
        stop_player();
        http_reply(fd, 200, "stopped");
        return;
    }

    if (!strncmp(target, "/play?", 6)) {
        char *src_arg = strstr(target + 6, "src=");
        char decoded[PATH_MAX_LOCAL], path[PATH_MAX_LOCAL];
        if (!src_arg) { http_reply(fd, 400, "missing src"); return; }
        src_arg += 4;
        {
            char *amp = strchr(src_arg, '&');
            if (amp) *amp = '\0';
        }
        url_decode(decoded, sizeof(decoded), src_arg);
        fprintf(stderr, "kanki-audio: request src=%s\n", decoded);

        if (is_remote_url(decoded)) {
            start_source(decoded, 1);
            http_reply(fd, 200, "remote playing");
            return;
        }

        if (!resolve_media_path(decoded, path, sizeof(path))) {
            fprintf(stderr, "kanki-audio: local media unavailable: %s\n", decoded);
            http_reply(fd, 404, "media not found");
            return;
        }
        start_source(path, 0);
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

    fprintf(stderr, "kanki-audio: starting, media=%s player=%s loader=%s\n",
        getenv("KANKI_MEDIA_DIR") ? getenv("KANKI_MEDIA_DIR") : "(unset)",
        getenv("KANKI_GST_PLAYER") ? getenv("KANKI_GST_PLAYER") : "(unset)",
        getenv("KANKI_GST_LOADER") ? getenv("KANKI_GST_LOADER") : "(unset)");
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
