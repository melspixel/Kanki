#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "kindle_webkit_scale.h"

static char calls[64];
static size_t call_count;
static float fake_density;
static float last_zoom;
static int fixed_width;
static int fixed_height;

static void record(char value)
{
    if (call_count + 1 >= sizeof(calls)) {
        fprintf(stderr, "call log overflow\n");
        exit(2);
    }
    calls[call_count++] = value;
    calls[call_count] = '\0';
}

static void reset(void)
{
    memset(calls, 0, sizeof(calls));
    call_count = 0;
    fake_density = 1.0f;
    last_zoom = 0.0f;
    fixed_width = 0;
    fixed_height = 0;
}

static void fake_w3c(int enabled) { record(enabled ? 'W' : 'w'); }
static float fake_get_density(void) { record('D'); return fake_density; }
static void fake_full_zoom(void *view, int enabled)
{
    (void)view;
    record(enabled ? 'F' : 'f');
}
static void fake_zoom(void *view, float zoom)
{
    (void)view;
    last_zoom = zoom;
    record('Z');
}
static void fake_fixed(void *view, int enabled)
{
    (void)view;
    record(enabled ? 'L' : 'l');
}
static void fake_fixed_width(void *view, int width)
{
    (void)view;
    fixed_width = width;
    record('X');
}
static void fake_fixed_height(void *view, int height)
{
    (void)view;
    fixed_height = height;
    record('Y');
}

static void expect(int condition, const char *message)
{
    if (!condition) {
        fprintf(stderr, "FAIL: %s (calls=%s zoom=%.4f)\n",
                message, calls, (double)last_zoom);
        exit(1);
    }
}

static KankiWebKitApi full_api(void)
{
    KankiWebKitApi api;
    memset(&api, 0, sizeof(api));
    api.set_w3c_css_pixels = fake_w3c;
    api.get_pixel_density = fake_get_density;
    api.set_full_content_zoom = fake_full_zoom;
    api.set_zoom_level = fake_zoom;
    api.set_fixed_layout = fake_fixed;
    api.set_fixed_layout_width = fake_fixed_width;
    api.set_fixed_layout_height = fake_fixed_height;
    return api;
}

static void test_mesquite_sequence(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    fake_density = 3.125f;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) == KANKI_SCALE_NATIVE,
           "native density should succeed");
    expect(strcmp(calls, "WDFZ") == 0,
           "call order must match W3C, density, full-content zoom, zoom");
    expect(last_zoom == 3.125f, "zoom must equal native pixel density");
    expect(result.enabled_w3c_css_pixels == 1, "W3C CSS pixels must be reported");
    expect(result.enabled_full_content_zoom == 1, "full-content zoom must be reported");
}

static void test_density_one(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    fake_density = 1.0f;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) == KANKI_SCALE_NATIVE,
           "density 1 should still be native");
    expect(strcmp(calls, "WDZ") == 0,
           "full-content zoom is unnecessary when density is 1");
    expect(last_zoom == 1.0f, "density 1 should apply zoom 1");
}

static void test_missing_full_content_zoom_fallback(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    fake_density = 3.125f;
    api.set_full_content_zoom = NULL;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) ==
               KANKI_SCALE_FALLBACK_MISSING_API,
           "density scaling without full-content zoom must fall back");
    expect(strcmp(calls, "WDZ") == 0,
           "missing full-content zoom must not apply the panel density");
    expect(last_zoom == 1.0f,
           "missing full-content zoom fallback must remain at zoom 1");
    expect(result.reported_density == 3.125f,
           "raw density must remain available for diagnostics");
    expect(result.applied_zoom == 1.0f,
           "applied zoom must record the safe fallback");
    expect(result.enabled_full_content_zoom == 0,
           "full-content zoom must not be reported as enabled");
}

static void test_invalid_density_fallback(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    fake_density = 0.0f;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) ==
               KANKI_SCALE_FALLBACK_INVALID_DENSITY,
           "invalid density should fall back");
    expect(strcmp(calls, "WDFZ") == 0, "fallback should use full-content zoom at 1");
    expect(last_zoom == 1.0f, "invalid density fallback must be zoom 1");
    expect(result.reported_density == 0.0f,
           "invalid raw density must remain visible for diagnostics");
    expect(result.applied_zoom == 1.0f,
           "invalid density must be distinguished from applied fallback zoom");
}

static void test_missing_api_fallback(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    api.set_w3c_css_pixels = NULL;
    api.get_pixel_density = NULL;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) ==
               KANKI_SCALE_FALLBACK_MISSING_API,
           "missing Kindle API should fall back");
    expect(strcmp(calls, "FZ") == 0, "fallback should only enable full zoom and zoom 1");
    expect(last_zoom == 1.0f, "missing API fallback must be zoom 1");
}

static void test_no_zoom_is_fatal(void)
{
    KankiWebKitApi api = full_api();
    KankiScaleResult result;
    reset();
    api.set_zoom_level = NULL;
    expect(kanki_webkit_apply_native_scale((void *)1, &api, &result) ==
               KANKI_SCALE_FATAL_NO_ZOOM_API,
           "missing normal WebKit zoom API is fatal");
    expect(strcmp(calls, "") == 0, "fatal path must not call partial API set");
}

static void test_fixed_layout_is_explicit(void)
{
    KankiWebKitApi api = full_api();
    reset();
    expect(kanki_webkit_apply_fixed_layout((void *)1, &api, 420, 800) == 1,
           "valid fixed layout should apply");
    expect(strcmp(calls, "LXY") == 0, "fixed layout call order must be enable, width, height");
    expect(fixed_width == 420 && fixed_height == 800, "fixed layout dimensions must survive");

    reset();
    expect(kanki_webkit_apply_fixed_layout((void *)1, &api, 0, 800) == 0,
           "invalid fixed layout should not apply");
    expect(strcmp(calls, "") == 0, "invalid fixed layout must not make calls");
}

int main(void)
{
    test_mesquite_sequence();
    test_density_one();
    test_missing_full_content_zoom_fallback();
    test_invalid_density_fallback();
    test_missing_api_fallback();
    test_no_zoom_is_fatal();
    test_fixed_layout_is_explicit();
    puts("test_scale: ok");
    return 0;
}
