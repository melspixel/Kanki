#ifndef KANKI_NEXT_KINDLE_WEBKIT_SCALE_H
#define KANKI_NEXT_KINDLE_WEBKIT_SCALE_H

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*KankiSetW3CCssPixelsFn)(int enabled);
typedef float (*KankiGetPixelDensityFn)(void);
typedef void (*KankiSetFullContentZoomFn)(void *web_view, int enabled);
typedef void (*KankiSetZoomLevelFn)(void *web_view, float zoom_level);
typedef void (*KankiSetFixedLayoutFn)(void *web_view, int enabled);
typedef void (*KankiSetFixedLayoutDimensionFn)(void *web_view, int value);
typedef void *(*KankiResolveSymbolFn)(void *handle, const char *name);

typedef struct {
    KankiSetW3CCssPixelsFn set_w3c_css_pixels;
    KankiGetPixelDensityFn get_pixel_density;
    KankiSetFullContentZoomFn set_full_content_zoom;
    KankiSetZoomLevelFn set_zoom_level;
    KankiSetFixedLayoutFn set_fixed_layout;
    KankiSetFixedLayoutDimensionFn set_fixed_layout_width;
    KankiSetFixedLayoutDimensionFn set_fixed_layout_height;
} KankiWebKitApi;

typedef enum {
    KANKI_SCALE_NATIVE = 0,
    KANKI_SCALE_FALLBACK_MISSING_API = 1,
    KANKI_SCALE_FALLBACK_INVALID_DENSITY = 2,
    KANKI_SCALE_FATAL_NO_ZOOM_API = 3
} KankiScaleStatus;

typedef struct {
    KankiScaleStatus status;
    float reported_density;
    float applied_zoom;
    int enabled_w3c_css_pixels;
    int enabled_full_content_zoom;
} KankiScaleResult;

void kanki_webkit_api_clear(KankiWebKitApi *api);
int kanki_webkit_api_resolve(
    void *webkit_handle,
    KankiResolveSymbolFn resolve,
    KankiWebKitApi *api
);

/* Must be called before creating the first WebView when the Lab126 global
 * CSS-pixel switch is available. It is safe to call again later. */
int kanki_webkit_prepare_global_css_pixels(const KankiWebKitApi *api);

/* Reproduces Mesquite's observed native sequence:
 *   set_useW3CStd_cssPixelsPerInch(true)
 *   density = get_pixel_density()
 *   set_full_content_zoom(view, true) when density != 1
 *   set_zoom_level(view, density)
 *
 * It deliberately does not multiply by GTK/UI scale or a user font scale.
 */
KankiScaleStatus kanki_webkit_apply_native_scale(
    void *web_view,
    const KankiWebKitApi *api,
    KankiScaleResult *result
);

/* Fixed layout is opt-in. Responsive Anki templates should not be forced into
 * it merely to compensate for an incorrect CSS-pixel configuration. */
int kanki_webkit_apply_fixed_layout(
    void *web_view,
    const KankiWebKitApi *api,
    int width,
    int height
);

#ifdef __cplusplus
}
#endif

#endif
