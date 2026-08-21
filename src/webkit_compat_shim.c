#define _GNU_SOURCE
typedef unsigned int size_t;
extern void *malloc(size_t);
extern void free(void *);
extern void *dlsym(void *, const char *);
extern char *getenv(const char *);
extern int open(const char *, int, ...);
extern int close(int);
extern int write(int, const void *, unsigned int);
#define RTLD_NEXT ((void *)-1L)
#define NULL ((void*)0)
#define O_WRONLY 1
#define O_CREAT 64
#define O_TRUNC 512

#include "kanki_embedded_assets.h"

static size_t k_strlen(const char *s) { size_t n=0; while (s && s[n]) n++; return n; }
static void k_memcpy(char *d, const char *s, size_t n) { while (n--) *d++=*s++; }
static const char *k_strstr(const char *h, const char *n) {
    size_t nl=k_strlen(n); if (!nl) return h;
    for (; h && *h; h++) { size_t i=0; while (i<nl && h[i]==n[i]) i++; if (i==nl) return h; }
    return (const char*)0;
}

static unsigned int render_seq = 0;
static const unsigned int RENDER_CAPTURE_LIMIT = 40;
static const char DEBUG_PREFIX[] = "/mnt/us/extensions/ranki/render-debug/render-";

static int debug_enabled(void) {
    const char *v = getenv("KANKI_RENDER_DEBUG");
    return v && *v && *v != '0';
}

static size_t u32_ascii(unsigned int v, char *buf) {
    char tmp[16];
    size_t n=0, i;
    if (!v) { buf[0]='0'; return 1; }
    while (v && n < sizeof(tmp)) { tmp[n++] = (char)('0' + (v % 10)); v /= 10; }
    for (i=0; i<n; i++) buf[i] = tmp[n-1-i];
    return n;
}

static int write_all(int fd, const char *data, size_t len) {
    while (len) {
        int n = write(fd, data, len);
        if (n <= 0) return 0;
        data += n;
        len -= (size_t)n;
    }
    return 1;
}

static void log_literal(const char *text) {
    write_all(2, text, k_strlen(text));
}

static int open_render_file(unsigned int seq, const char *suffix) {
    char path[160];
    char num[16];
    size_t p=0, n, i;
    n = k_strlen(DEBUG_PREFIX);
    if (n >= sizeof(path)) return -1;
    k_memcpy(path+p, DEBUG_PREFIX, n); p += n;
    n = u32_ascii(seq, num);
    if (p+n >= sizeof(path)) return -1;
    k_memcpy(path+p, num, n); p += n;
    n = k_strlen(suffix);
    if (p+n+1 >= sizeof(path)) return -1;
    for (i=0; i<n; i++) path[p++] = suffix[i];
    path[p] = '\0';
    return open(path, O_WRONLY | O_CREAT | O_TRUNC, 0644);
}

static void dump_render_file(unsigned int seq, const char *suffix, const char *data, size_t len) {
    int fd;
    if (!debug_enabled() || seq > RENDER_CAPTURE_LIMIT || !data) return;
    fd = open_render_file(seq, suffix);
    if (fd < 0) return;
    write_all(fd, data, len);
    close(fd);
}

static void write_num(int fd, unsigned int v) {
    char buf[16];
    size_t n = u32_ascii(v, buf);
    write_all(fd, buf, n);
}

static void dump_render_meta(unsigned int seq, const char *base_uri, size_t input_len, size_t patched_len) {
    int fd;
    if (!debug_enabled() || seq > RENDER_CAPTURE_LIMIT) return;
    fd = open_render_file(seq, "-meta.txt");
    if (fd < 0) return;
    write_all(fd, "render_id=", 10); write_num(fd, seq); write_all(fd, "\n", 1);
    write_all(fd, "base_uri=", 9);
    if (base_uri) write_all(fd, base_uri, k_strlen(base_uri));
    write_all(fd, "\ninput_bytes=", 13); write_num(fd, (unsigned int)input_len);
    write_all(fd, "\npatched_bytes=", 15); write_num(fd, (unsigned int)patched_len);
    write_all(fd, "\n", 1);
    close(fd);
}

static void log_render_native(unsigned int seq, size_t input_len, size_t patched_len) {
    if (!debug_enabled()) return;
    if (seq == RENDER_CAPTURE_LIMIT + 1) {
        log_literal("KANKI_RENDER_NATIVE|capture-limit-reached|40\n");
        return;
    }
    if (seq > RENDER_CAPTURE_LIMIT) return;
    write_all(2, "KANKI_RENDER_NATIVE|id=", 23); write_num(2, seq);
    write_all(2, "|input=", 7); write_num(2, (unsigned int)input_len);
    write_all(2, "|patched=", 9); write_num(2, (unsigned int)patched_len);
    write_all(2, "\n", 1);
}

/* Kindle/Lab126 WebKit scale oracle. These extensions are resolved at runtime
 * so the shared object remains usable on systems that only expose stock
 * WebKitGTK 1.x. */
typedef void *(*web_view_new_fn)(void);
typedef void (*load_html_fn)(void *web_view, const char *content, const char *base_uri);
typedef void (*set_zoom_fn)(void *web_view, float zoom_level);
typedef void (*set_w3c_css_pixels_fn)(int enabled);
typedef float (*get_pixel_density_fn)(void);
typedef void (*set_full_content_zoom_fn)(void *web_view, int enabled);

static set_w3c_css_pixels_fn k_set_w3c_css_pixels = NULL;
static get_pixel_density_fn k_get_pixel_density = NULL;
static set_full_content_zoom_fn k_set_full_content_zoom = NULL;
static int scale_api_resolved = 0;
static int scale_mode = 0; /* 0 unknown, 1 native, 2 fallback missing API, 3 fallback invalid density */
static int scale_mode_logged = 0;

static void resolve_scale_api(void) {
    if (scale_api_resolved) return;
    scale_api_resolved = 1;
    k_set_w3c_css_pixels = (set_w3c_css_pixels_fn)dlsym(
        RTLD_NEXT, "webkit_web_view_set_useW3CStd_cssPixelsPerInch");
    k_get_pixel_density = (get_pixel_density_fn)dlsym(
        RTLD_NEXT, "webkit_web_view_get_pixel_density");
    k_set_full_content_zoom = (set_full_content_zoom_fn)dlsym(
        RTLD_NEXT, "webkit_web_view_set_full_content_zoom");
}

static void prepare_global_css_pixels(void) {
    resolve_scale_api();
    if (k_set_w3c_css_pixels) k_set_w3c_css_pixels(1);
}

static int density_is_valid(float density) {
    return density == density && density >= 0.75f && density <= 4.50f;
}

static void log_scale_mode_once(int mode) {
    if (scale_mode_logged == mode) return;
    scale_mode_logged = mode;
    if (mode == 1) log_literal("KANKI_SCALE|native-css-pixels|full-content-zoom\n");
    else if (mode == 3) log_literal("KANKI_SCALE|fallback|invalid-pixel-density|zoom=1\n");
    else log_literal("KANKI_SCALE|fallback|missing-lab126-api|zoom=1\n");
}

void *webkit_web_view_new(void) {
    static web_view_new_fn real_fn = NULL;
    if (!real_fn) {
        real_fn = (web_view_new_fn)dlsym(RTLD_NEXT, "webkit_web_view_new");
        if (!real_fn) return NULL;
    }
    /* Mesquite enables the global W3C CSS-pixel mode before creating views. */
    prepare_global_css_pixels();
    return real_fn();
}

static const char STYLE_OPEN[] = "<style id=\"kanki-reviewer-compat\">";
static const char STYLE_CLOSE[] = "</style>";
static const char RID_OPEN[] = "<script>window.__kankiRenderId=";
static const char RID_CLOSE[] = ";</script>";
static const char SCALE_NATIVE[] = "<script>window.__kankiNativeCssPixels=1;document.documentElement.className+=' kanki-native-scale';</script>";
static const char SCALE_FALLBACK[] = "<script>window.__kankiNativeCssPixels=0;document.documentElement.className+=' kanki-scale-fallback';</script>";
static const char SCRIPT_OPEN[] = "<script>";
static const char SCRIPT_CLOSE[] = "</script>";

static char *inject_compat(const char *content, unsigned int seq)
{
    const char *head_open, *head_close, *scale_script;
    char rid[16];
    size_t rid_len;
    size_t content_len, css_len, js_len, so_len, sc_len, ro_len, rc_len;
    size_t ss_len, jo_len, jc_len, total;
    char *out, *p;

    if (!content) return NULL;
    if (k_strstr(content, "kanki-reviewer-compat") != NULL) return NULL;

    scale_script = scale_mode == 1 ? SCALE_NATIVE : SCALE_FALLBACK;
    content_len = k_strlen(content);
    css_len = k_strlen(KANKI_REVIEWER_CSS);
    js_len = k_strlen(KANKI_COMPAT_JS);
    rid_len = u32_ascii(seq, rid);
    so_len = sizeof(STYLE_OPEN) - 1;
    sc_len = sizeof(STYLE_CLOSE) - 1;
    ro_len = sizeof(RID_OPEN) - 1;
    rc_len = sizeof(RID_CLOSE) - 1;
    ss_len = k_strlen(scale_script);
    jo_len = sizeof(SCRIPT_OPEN) - 1;
    jc_len = sizeof(SCRIPT_CLOSE) - 1;
    total = content_len + so_len + css_len + sc_len + ro_len + rid_len + rc_len +
            ss_len + jo_len + js_len + jc_len;

    out = (char *)malloc(total + 1);
    if (!out) return NULL;
    p = out;

    head_open = k_strstr(content, "<head>");
    head_close = k_strstr(content, "</head>");

    if (head_open && head_close && head_open < head_close) {
        size_t through_open = (size_t)(head_open - content) + 6;
        size_t middle_len = (size_t)(head_close - (content + through_open));
        size_t tail_len = content_len - (size_t)(head_close - content);

        k_memcpy(p, content, through_open); p += through_open;
        k_memcpy(p, STYLE_OPEN, so_len); p += so_len;
        k_memcpy(p, KANKI_REVIEWER_CSS, css_len); p += css_len;
        k_memcpy(p, STYLE_CLOSE, sc_len); p += sc_len;
        k_memcpy(p, content + through_open, middle_len); p += middle_len;
        k_memcpy(p, RID_OPEN, ro_len); p += ro_len;
        k_memcpy(p, rid, rid_len); p += rid_len;
        k_memcpy(p, RID_CLOSE, rc_len); p += rc_len;
        k_memcpy(p, scale_script, ss_len); p += ss_len;
        k_memcpy(p, SCRIPT_OPEN, jo_len); p += jo_len;
        k_memcpy(p, KANKI_COMPAT_JS, js_len); p += js_len;
        k_memcpy(p, SCRIPT_CLOSE, jc_len); p += jc_len;
        k_memcpy(p, head_close, tail_len); p += tail_len;
    } else {
        k_memcpy(p, STYLE_OPEN, so_len); p += so_len;
        k_memcpy(p, KANKI_REVIEWER_CSS, css_len); p += css_len;
        k_memcpy(p, STYLE_CLOSE, sc_len); p += sc_len;
        k_memcpy(p, RID_OPEN, ro_len); p += ro_len;
        k_memcpy(p, rid, rid_len); p += rid_len;
        k_memcpy(p, RID_CLOSE, rc_len); p += rc_len;
        k_memcpy(p, scale_script, ss_len); p += ss_len;
        k_memcpy(p, SCRIPT_OPEN, jo_len); p += jo_len;
        k_memcpy(p, KANKI_COMPAT_JS, js_len); p += js_len;
        k_memcpy(p, SCRIPT_CLOSE, jc_len); p += jc_len;
        k_memcpy(p, content, content_len); p += content_len;
    }
    *p = '\0';
    return out;
}

void webkit_web_view_load_html_string(void *web_view, const char *content, const char *base_uri)
{
    static load_html_fn real_fn = NULL;
    char *patched;
    unsigned int seq;
    size_t input_len, patched_len;
    if (!real_fn) {
        real_fn = (load_html_fn)dlsym(RTLD_NEXT, "webkit_web_view_load_html_string");
        if (!real_fn) return;
    }

    seq = ++render_seq;
    input_len = content ? k_strlen(content) : 0;
    dump_render_file(seq, "-input.html", content, input_len);

    patched = inject_compat(content, seq);
    if (patched) {
        patched_len = k_strlen(patched);
        dump_render_file(seq, "-patched.html", patched, patched_len);
        dump_render_meta(seq, base_uri, input_len, patched_len);
        log_render_native(seq, input_len, patched_len);
        real_fn(web_view, patched, base_uri);
        free(patched);
    } else {
        dump_render_meta(seq, base_uri, input_len, input_len);
        log_render_native(seq, input_len, input_len);
        real_fn(web_view, content, base_uri);
    }
}

void webkit_web_view_set_zoom_level(void *web_view, float requested_zoom)
{
    static set_zoom_fn real_fn = NULL;
    float density = 1.0f;
    (void)requested_zoom;

    if (!real_fn) {
        real_fn = (set_zoom_fn)dlsym(RTLD_NEXT, "webkit_web_view_set_zoom_level");
        if (!real_fn) return;
    }

    prepare_global_css_pixels();
    if (k_set_w3c_css_pixels && k_get_pixel_density && k_set_full_content_zoom) {
        density = k_get_pixel_density();
        if (density_is_valid(density)) {
            /* Full-content zoom is essential: without it WebKitGTK 1.x scales
             * text but not replaced elements such as images. */
            k_set_full_content_zoom(web_view, 1);
            real_fn(web_view, density);
            scale_mode = 1;
            log_scale_mode_once(scale_mode);
            return;
        }
        scale_mode = 3;
    } else {
        scale_mode = 2;
    }

    /* Never apply the panel density when full-content zoom is unavailable;
     * doing so recreates RAnki's text-only zoom defect. */
    if (k_set_full_content_zoom) k_set_full_content_zoom(web_view, 1);
    real_fn(web_view, 1.0f);
    log_scale_mode_once(scale_mode);
}

/* Upstream RAnki calls view.expand_all() after every deck-tree refresh. GTK
 * starts tree rows collapsed by default, so suppressing only this blanket call
 * gives a compact deck list while preserving normal click-to-expand behavior. */
void gtk_tree_view_expand_all(void *tree_view)
{
    (void)tree_view;
}
