#include "kindle_webkit_scale.h"

#include <stddef.h>
#include <string.h>

#define KANKI_MIN_DENSITY 0.75f
#define KANKI_MAX_DENSITY 4.50f
#define KANKI_DENSITY_EPSILON 0.001f

static int density_is_valid(float density)
{
    /* NaN is the only floating-point value unequal to itself. The range check
     * also rejects infinities without pulling libm into the Kindle binary. */
    return density == density &&
           density >= KANKI_MIN_DENSITY &&
           density <= KANKI_MAX_DENSITY;
}

static float absolute_float(float value)
{
    return value < 0.0f ? -value : value;
}

void kanki_webkit_api_clear(KankiWebKitApi *api)
{
    if (api != NULL) {
        memset(api, 0, sizeof(*api));
    }
}

int kanki_webkit_api_resolve(
    void *webkit_handle,
    KankiResolveSymbolFn resolve,
    KankiWebKitApi *api
)
{
    if (webkit_handle == NULL || resolve == NULL || api == NULL) {
        return 0;
    }

    kanki_webkit_api_clear(api);
    api->set_w3c_css_pixels = (KankiSetW3CCssPixelsFn)
        resolve(webkit_handle, "webkit_web_view_set_useW3CStd_cssPixelsPerInch");
    api->get_pixel_density = (KankiGetPixelDensityFn)
        resolve(webkit_handle, "webkit_web_view_get_pixel_density");
    api->set_full_content_zoom = (KankiSetFullContentZoomFn)
        resolve(webkit_handle, "webkit_web_view_set_full_content_zoom");
    api->set_zoom_level = (KankiSetZoomLevelFn)
        resolve(webkit_handle, "webkit_web_view_set_zoom_level");
    api->set_fixed_layout = (KankiSetFixedLayoutFn)
        resolve(webkit_handle, "webkit_web_view_set_fixed_layout");
    api->set_fixed_layout_width = (KankiSetFixedLayoutDimensionFn)
        resolve(webkit_handle, "webkit_web_view_set_fixed_layout_width");
    api->set_fixed_layout_height = (KankiSetFixedLayoutDimensionFn)
        resolve(webkit_handle, "webkit_web_view_set_fixed_layout_height");

    return api->set_zoom_level != NULL;
}

int kanki_webkit_prepare_global_css_pixels(const KankiWebKitApi *api)
{
    if (api == NULL || api->set_w3c_css_pixels == NULL) {
        return 0;
    }
    api->set_w3c_css_pixels(1);
    return 1;
}

KankiScaleStatus kanki_webkit_apply_native_scale(
    void *web_view,
    const KankiWebKitApi *api,
    KankiScaleResult *result
)
{
    KankiScaleStatus status;
    float reported_density = 1.0f;
    float applied_zoom = 1.0f;
    int enabled_w3c = 0;
    int enabled_full_zoom = 0;

    if (result != NULL) {
        memset(result, 0, sizeof(*result));
        result->reported_density = 1.0f;
        result->applied_zoom = 1.0f;
    }

    if (api == NULL || api->set_zoom_level == NULL) {
        status = KANKI_SCALE_FATAL_NO_ZOOM_API;
        if (result != NULL) {
            result->status = status;
        }
        return status;
    }

    if (api->set_w3c_css_pixels != NULL && api->get_pixel_density != NULL) {
        api->set_w3c_css_pixels(1);
        enabled_w3c = 1;
        reported_density = api->get_pixel_density();
        if (density_is_valid(reported_density)) {
            if (absolute_float(reported_density - 1.0f) > KANKI_DENSITY_EPSILON &&
                api->set_full_content_zoom == NULL) {
                /* Applying the panel density without full-content zoom would
                 * recreate RAnki's text-only scaling bug. Keep the document at
                 * 1:1 and report the missing native capability instead. */
                applied_zoom = 1.0f;
                api->set_zoom_level(web_view, applied_zoom);
                status = KANKI_SCALE_FALLBACK_MISSING_API;
            } else {
                applied_zoom = reported_density;
                if (absolute_float(reported_density - 1.0f) > KANKI_DENSITY_EPSILON) {
                    api->set_full_content_zoom(web_view, 1);
                    enabled_full_zoom = 1;
                }
                api->set_zoom_level(web_view, applied_zoom);
                status = KANKI_SCALE_NATIVE;
            }
        } else {
            applied_zoom = 1.0f;
            if (api->set_full_content_zoom != NULL) {
                api->set_full_content_zoom(web_view, 1);
                enabled_full_zoom = 1;
            }
            api->set_zoom_level(web_view, applied_zoom);
            status = KANKI_SCALE_FALLBACK_INVALID_DENSITY;
        }
    } else {
        if (api->set_full_content_zoom != NULL) {
            api->set_full_content_zoom(web_view, 1);
            enabled_full_zoom = 1;
        }
        applied_zoom = 1.0f;
        api->set_zoom_level(web_view, applied_zoom);
        status = KANKI_SCALE_FALLBACK_MISSING_API;
    }

    if (result != NULL) {
        result->status = status;
        result->reported_density = reported_density;
        result->applied_zoom = applied_zoom;
        result->enabled_w3c_css_pixels = enabled_w3c;
        result->enabled_full_content_zoom = enabled_full_zoom;
    }
    return status;
}

int kanki_webkit_apply_fixed_layout(
    void *web_view,
    const KankiWebKitApi *api,
    int width,
    int height
)
{
    if (api == NULL ||
        api->set_fixed_layout == NULL ||
        api->set_fixed_layout_width == NULL ||
        api->set_fixed_layout_height == NULL ||
        width <= 0 || height <= 0) {
        return 0;
    }

    api->set_fixed_layout(web_view, 1);
    api->set_fixed_layout_width(web_view, width);
    api->set_fixed_layout_height(web_view, height);
    return 1;
}
