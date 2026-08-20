#define _GNU_SOURCE
typedef unsigned int size_t;
extern void *malloc(size_t);
extern void free(void *);
extern void *dlsym(void *, const char *);
#define RTLD_NEXT ((void *)-1L)
#define NULL ((void*)0)

#include "kanki_embedded_assets.h"

static size_t k_strlen(const char *s) { size_t n=0; while (s && s[n]) n++; return n; }
static void k_memcpy(char *d, const char *s, size_t n) { while (n--) *d++=*s++; }
static const char *k_strstr(const char *h, const char *n) {
    size_t nl=k_strlen(n); if (!nl) return h;
    for (; h && *h; h++) { size_t i=0; while (i<nl && h[i]==n[i]) i++; if (i==nl) return h; }
    return (const char*)0;
}

typedef void (*load_html_fn)(void *web_view, const char *content, const char *base_uri);
typedef void (*set_zoom_fn)(void *web_view, float zoom_level);

static const char STYLE_OPEN[] = "<style id=\"kanki-reviewer-compat\">";
static const char STYLE_CLOSE_SCRIPT_OPEN[] = "</style><script>";
static const char SCRIPT_CLOSE[] = "</script>";

static char *inject_compat(const char *content)
{
    const char *head;
    size_t content_len, css_len, js_len, a_len, b_len, c_len, prefix_len, total;
    char *out, *p;

    if (!content) return NULL;
    if (k_strstr(content, "kanki-reviewer-compat") != NULL) return NULL;

    content_len = k_strlen(content);
    css_len = k_strlen(KANKI_REVIEWER_CSS);
    js_len = k_strlen(KANKI_COMPAT_JS);
    a_len = sizeof(STYLE_OPEN) - 1;
    b_len = sizeof(STYLE_CLOSE_SCRIPT_OPEN) - 1;
    c_len = sizeof(SCRIPT_CLOSE) - 1;
    head = k_strstr(content, "</head>");
    prefix_len = head ? (size_t)(head - content) : 0;
    total = content_len + a_len + css_len + b_len + js_len + c_len;

    out = (char *)malloc(total + 1);
    if (!out) return NULL;
    p = out;

    if (head) {
        k_memcpy(p, content, prefix_len); p += prefix_len;
        k_memcpy(p, STYLE_OPEN, a_len); p += a_len;
        k_memcpy(p, KANKI_REVIEWER_CSS, css_len); p += css_len;
        k_memcpy(p, STYLE_CLOSE_SCRIPT_OPEN, b_len); p += b_len;
        k_memcpy(p, KANKI_COMPAT_JS, js_len); p += js_len;
        k_memcpy(p, SCRIPT_CLOSE, c_len); p += c_len;
        k_memcpy(p, head, content_len - prefix_len); p += content_len - prefix_len;
    } else {
        k_memcpy(p, STYLE_OPEN, a_len); p += a_len;
        k_memcpy(p, KANKI_REVIEWER_CSS, css_len); p += css_len;
        k_memcpy(p, STYLE_CLOSE_SCRIPT_OPEN, b_len); p += b_len;
        k_memcpy(p, KANKI_COMPAT_JS, js_len); p += js_len;
        k_memcpy(p, SCRIPT_CLOSE, c_len); p += c_len;
        k_memcpy(p, content, content_len); p += content_len;
    }
    *p = '\0';
    return out;
}

void webkit_web_view_load_html_string(void *web_view, const char *content, const char *base_uri)
{
    static load_html_fn real_fn = NULL;
    char *patched;
    if (!real_fn) {
        real_fn = (load_html_fn)dlsym(RTLD_NEXT, "webkit_web_view_load_html_string");
        if (!real_fn) return;
    }
    patched = inject_compat(content);
    if (patched) {
        real_fn(web_view, patched, base_uri);
        free(patched);
    } else {
        real_fn(web_view, content, base_uri);
    }
}

void webkit_web_view_set_zoom_level(void *web_view, float zoom_level)
{
    static set_zoom_fn real_fn = NULL;
    if (!real_fn) {
        real_fn = (set_zoom_fn)dlsym(RTLD_NEXT, "webkit_web_view_set_zoom_level");
        if (!real_fn) return;
    }
    /* Keep one uniform physical scale, while preserving every relative font
       size supplied by the deck itself. */
    if (zoom_level > 1.25f) zoom_level = 1.25f;
    if (zoom_level < 0.90f) zoom_level = 0.90f;
    real_fn(web_view, zoom_level);
}

/* Upstream Ranki calls view.expand_all() after every deck-tree refresh. GTK
 * starts tree rows collapsed by default, so suppressing only this blanket call
 * gives a compact deck list while preserving normal click-to-expand behavior. */
void gtk_tree_view_expand_all(void *tree_view)
{
    (void)tree_view;
}
