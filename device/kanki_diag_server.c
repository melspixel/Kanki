#define _POSIX_C_SOURCE 200809L

#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>

#define KANKI_DIR "/mnt/us/extensions/kanki"
#define DEBUG_DIR KANKI_DIR "/render-debug"
#define METRICS_PATH DEBUG_DIR "/metrics.log"
#define CAPTURE_SENTINEL KANKI_DIR "/enable-render-capture"
#define PORT 17393
#define REQUEST_CAP 8192
#define FIELD_CAP 4096

static volatile sig_atomic_t running = 1;

static void on_signal(int sig) {
    (void)sig;
    running = 0;
}

static void log_line(const char *format, ...) {
    FILE *file = fopen(METRICS_PATH, "a");
    va_list args;
    time_t now;
    struct tm value;
    char stamp[64];
    if (!file) return;
    now = time(NULL);
    localtime_r(&now, &value);
    strftime(stamp, sizeof(stamp), "%Y-%m-%dT%H:%M:%S", &value);
    fprintf(file, "%s ", stamp);
    va_start(args, format);
    vfprintf(file, format, args);
    va_end(args);
    fputc('\n', file);
    fclose(file);
}

static int hex_value(char ch) {
    if (ch >= '0' && ch <= '9') return ch - '0';
    if (ch >= 'a' && ch <= 'f') return ch - 'a' + 10;
    if (ch >= 'A' && ch <= 'F') return ch - 'A' + 10;
    return -1;
}

static int decode_component(const char *source, size_t length, char *output, size_t capacity) {
    size_t i = 0;
    size_t j = 0;
    if (!output || capacity == 0) return 0;
    while (i < length && j + 1 < capacity) {
        if (source[i] == '%' && i + 2 < length) {
            int high = hex_value(source[i + 1]);
            int low = hex_value(source[i + 2]);
            if (high >= 0 && low >= 0) {
                output[j++] = (char)((high << 4) | low);
                i += 3;
                continue;
            }
        }
        output[j++] = source[i] == '+' ? ' ' : source[i];
        i += 1;
    }
    output[j] = '\0';
    return i == length;
}

static int query_value(const char *query, const char *key, char *output, size_t capacity) {
    size_t key_len = strlen(key);
    const char *cursor = query;
    if (!query) return 0;
    while (*cursor) {
        const char *amp = strchr(cursor, '&');
        const char *equals = strchr(cursor, '=');
        const char *end = amp ? amp : cursor + strlen(cursor);
        if (equals && equals < end && (size_t)(equals - cursor) == key_len &&
            strncmp(cursor, key, key_len) == 0) {
            return decode_component(equals + 1, (size_t)(end - equals - 1), output, capacity);
        }
        if (!amp) break;
        cursor = amp + 1;
    }
    return 0;
}

static int safe_token(const char *value) {
    const unsigned char *p = (const unsigned char *)value;
    if (!value || !*value) return 0;
    while (*p) {
        if (!((*p >= 'a' && *p <= 'z') || (*p >= 'A' && *p <= 'Z') ||
              (*p >= '0' && *p <= '9') || *p == '-' || *p == '_')) return 0;
        p += 1;
    }
    return 1;
}

static void respond(int client, const char *status) {
    char buffer[256];
    int length = snprintf(buffer, sizeof(buffer),
                          "HTTP/1.1 %s\r\nContent-Length: 0\r\nConnection: close\r\n"
                          "Cache-Control: no-store\r\n\r\n",
                          status);
    if (length > 0) (void)write(client, buffer, (size_t)length);
}

static void handle_metric(const char *query) {
    char id[64] = "unknown";
    char side[32] = "unknown";
    char phase[32] = "unknown";
    char body[256] = "";
    char width[32] = "";
    char height[32] = "";
    char qa_width[32] = "";
    char qa_height[32] = "";
    char scroll_width[32] = "";
    char scroll_height[32] = "";
    char dpr[32] = "";
    char elements[32] = "";
    (void)query_value(query, "id", id, sizeof(id));
    (void)query_value(query, "side", side, sizeof(side));
    (void)query_value(query, "phase", phase, sizeof(phase));
    (void)query_value(query, "body", body, sizeof(body));
    (void)query_value(query, "iw", width, sizeof(width));
    (void)query_value(query, "ih", height, sizeof(height));
    (void)query_value(query, "qw", qa_width, sizeof(qa_width));
    (void)query_value(query, "qh", qa_height, sizeof(qa_height));
    (void)query_value(query, "sw", scroll_width, sizeof(scroll_width));
    (void)query_value(query, "sh", scroll_height, sizeof(scroll_height));
    (void)query_value(query, "dpr", dpr, sizeof(dpr));
    (void)query_value(query, "elements", elements, sizeof(elements));
    log_line("METRIC id=%s side=%s phase=%s inner=%sx%s qa=%sx%s scroll=%sx%s dpr=%s elements=%s body=%s",
             id, side, phase, width, height, qa_width, qa_height, scroll_width, scroll_height,
             dpr, elements, body);
}

static void handle_element(const char *query) {
    char id[64] = "unknown";
    char side[32] = "unknown";
    char phase[32] = "unknown";
    char index[32] = "";
    char tag[48] = "";
    char cls[256] = "";
    char geometry[128] = "";
    char font[192] = "";
    char display[64] = "";
    (void)query_value(query, "id", id, sizeof(id));
    (void)query_value(query, "side", side, sizeof(side));
    (void)query_value(query, "phase", phase, sizeof(phase));
    (void)query_value(query, "i", index, sizeof(index));
    (void)query_value(query, "tag", tag, sizeof(tag));
    (void)query_value(query, "cls", cls, sizeof(cls));
    (void)query_value(query, "g", geometry, sizeof(geometry));
    (void)query_value(query, "font", font, sizeof(font));
    (void)query_value(query, "display", display, sizeof(display));
    log_line("ELEMENT id=%s side=%s phase=%s i=%s tag=%s class=%s geometry=%s font=%s display=%s",
             id, side, phase, index, tag, cls, geometry, font, display);
}

static void handle_capture(const char *query) {
    char id[64] = "";
    char side[32] = "";
    char kind[32] = "";
    char part[32] = "";
    char data[FIELD_CAP];
    char path[512];
    long part_number;
    FILE *file;
    if (access(CAPTURE_SENTINEL, F_OK) != 0) return;
    if (!query_value(query, "id", id, sizeof(id)) ||
        !query_value(query, "side", side, sizeof(side)) ||
        !query_value(query, "kind", kind, sizeof(kind)) ||
        !query_value(query, "part", part, sizeof(part)) ||
        !query_value(query, "data", data, sizeof(data))) return;
    if (!safe_token(id) || !safe_token(side) || !safe_token(kind)) return;
    part_number = strtol(part, NULL, 10);
    if (part_number < 0 || part_number > 4096) return;
    if (snprintf(path, sizeof(path), "%s/render-%s-%s-%s.txt", DEBUG_DIR, id, side, kind) >=
        (int)sizeof(path)) return;
    file = fopen(path, part_number == 0 ? "wb" : "ab");
    if (!file) return;
    fwrite(data, 1, strlen(data), file);
    fclose(file);
}

static void handle_client(int client) {
    char request[REQUEST_CAP];
    ssize_t got;
    char method[16];
    char target[REQUEST_CAP];
    char *query;
    got = read(client, request, sizeof(request) - 1);
    if (got <= 0) return;
    request[got] = '\0';
    if (sscanf(request, "%15s %8191s", method, target) != 2 || strcmp(method, "GET") != 0) {
        respond(client, "405 Method Not Allowed");
        return;
    }
    query = strchr(target, '?');
    if (query) *query++ = '\0';
    if (strcmp(target, "/metric") == 0) {
        handle_metric(query);
        respond(client, "204 No Content");
    } else if (strcmp(target, "/element") == 0) {
        handle_element(query);
        respond(client, "204 No Content");
    } else if (strcmp(target, "/capture") == 0) {
        handle_capture(query);
        respond(client, "204 No Content");
    } else if (strcmp(target, "/health") == 0) {
        respond(client, "204 No Content");
    } else {
        respond(client, "404 Not Found");
    }
}

int main(void) {
    int server;
    int reuse = 1;
    struct sockaddr_in address;
    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_handler = on_signal;
    sigemptyset(&action.sa_mask);
    sigaction(SIGINT, &action, NULL);
    sigaction(SIGTERM, &action, NULL);
    signal(SIGPIPE, SIG_IGN);

    if (mkdir(DEBUG_DIR, 0755) != 0 && errno != EEXIST) {
        fprintf(stderr, "kanki-diag: cannot create %s: %s\n", DEBUG_DIR, strerror(errno));
        return 73;
    }
    log_line("START port=%d raw_capture=%s", PORT,
             access(CAPTURE_SENTINEL, F_OK) == 0 ? "enabled" : "disabled");

    server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return 74;
    (void)setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));
    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_port = htons(PORT);
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    if (bind(server, (struct sockaddr *)&address, sizeof(address)) != 0) {
        fprintf(stderr, "kanki-diag: bind failed: %s\n", strerror(errno));
        close(server);
        return 75;
    }
    if (listen(server, 8) != 0) {
        close(server);
        return 76;
    }

    while (running) {
        int client = accept(server, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        handle_client(client);
        close(client);
    }
    close(server);
    log_line("STOP");
    return 0;
}
