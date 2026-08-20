//! Kindle platform capability detection.
//!
//! The Paperwhite firmware extends WebKitGTK with Lab126 CSS-pixel and zoom
//! functions. Kanki resolves them at runtime and follows the same sequence as
//! the system browser. There is deliberately no synthetic 420px viewport.

use std::ffi::c_void;
use std::path::Path;

use libloading::Library;
use serde::{Deserialize, Serialize};
use thiserror::Error;

type SetW3cPixelsFn = unsafe extern "C" fn(i32);
type GetPixelDensityFn = unsafe extern "C" fn() -> f32;
type SetFullContentZoomFn = unsafe extern "C" fn(*mut c_void, i32);
type SetZoomLevelFn = unsafe extern "C" fn(*mut c_void, f32);

#[derive(Debug, Error)]
pub enum PlatformError {
    #[error("failed to load Kindle WebKit: {0}")]
    Load(#[from] libloading::Error),
    #[error("web view pointer was null")]
    NullWebView,
}

#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CssPixelCapabilities {
    pub w3c_css_pixels: bool,
    pub pixel_density: bool,
    pub full_content_zoom: bool,
    pub page_zoom: bool,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum CssPixelMode {
    NativeLab126,
    NativePartial,
    StandardWebKit,
}

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub struct CssPixelReport {
    pub mode: CssPixelMode,
    pub reported_density: f32,
    pub applied_zoom: f32,
    pub capabilities: CssPixelCapabilities,
}

#[derive(Clone, Copy)]
struct CssPixelApi {
    set_w3c_pixels: Option<SetW3cPixelsFn>,
    get_pixel_density: Option<GetPixelDensityFn>,
    set_full_content_zoom: Option<SetFullContentZoomFn>,
    set_zoom_level: Option<SetZoomLevelFn>,
}

/// Owns the WebKit library while copied function pointers remain in use.
pub struct KindleWebKit {
    api: CssPixelApi,
    _library: Library,
}

impl KindleWebKit {
    /// Load the device WebKit library and resolve optional Lab126 extensions.
    ///
    /// # Safety
    ///
    /// `path` must refer to the WebKit library used by the GTK process. The
    /// private function signatures are pinned from the audited target firmware.
    pub unsafe fn load(path: impl AsRef<Path>) -> Result<Self, PlatformError> {
        let library = unsafe { Library::new(path.as_ref())? };
        let api = unsafe { CssPixelApi::load(&library) };
        Ok(Self {
            api,
            _library: library,
        })
    }

    pub fn capabilities(&self) -> CssPixelCapabilities {
        self.api.capabilities()
    }

    /// Apply the native Kindle CSS-pixel sequence to one WebView.
    ///
    /// # Safety
    ///
    /// `web_view` must be a live `WebKitWebView*` created from this library and
    /// remain valid for the duration of the call.
    pub unsafe fn configure_css_pixels(
        &self,
        web_view: *mut c_void,
    ) -> Result<CssPixelReport, PlatformError> {
        if web_view.is_null() {
            return Err(PlatformError::NullWebView);
        }
        let capabilities = self.capabilities();
        if let Some(set_w3c_pixels) = self.api.set_w3c_pixels {
            unsafe { set_w3c_pixels(1) };
        }
        let reported_density = self
            .api
            .get_pixel_density
            .map(|get| unsafe { get() })
            .filter(|density| density.is_finite() && (0.5..=4.0).contains(density))
            .unwrap_or(1.0);
        let plan = plan_css_pixels(capabilities, reported_density);
        if matches!(plan.mode, CssPixelMode::NativeLab126) {
            if let Some(set_full_content_zoom) = self.api.set_full_content_zoom {
                unsafe { set_full_content_zoom(web_view, 1) };
            }
        }
        if let Some(set_zoom_level) = self.api.set_zoom_level {
            unsafe { set_zoom_level(web_view, plan.applied_zoom) };
        }
        Ok(plan)
    }
}

impl CssPixelApi {
    unsafe fn load(library: &Library) -> Self {
        Self {
            set_w3c_pixels: unsafe {
                library
                    .get::<SetW3cPixelsFn>(b"webkit_web_view_set_useW3CStd_cssPixelsPerInch\0")
                    .ok()
                    .map(|symbol| *symbol)
            },
            get_pixel_density: unsafe {
                library
                    .get::<GetPixelDensityFn>(b"webkit_web_view_get_pixel_density\0")
                    .ok()
                    .map(|symbol| *symbol)
            },
            set_full_content_zoom: unsafe {
                library
                    .get::<SetFullContentZoomFn>(b"webkit_web_view_set_full_content_zoom\0")
                    .ok()
                    .map(|symbol| *symbol)
            },
            set_zoom_level: unsafe {
                library
                    .get::<SetZoomLevelFn>(b"webkit_web_view_set_zoom_level\0")
                    .ok()
                    .map(|symbol| *symbol)
            },
        }
    }

    fn capabilities(self) -> CssPixelCapabilities {
        CssPixelCapabilities {
            w3c_css_pixels: self.set_w3c_pixels.is_some(),
            pixel_density: self.get_pixel_density.is_some(),
            full_content_zoom: self.set_full_content_zoom.is_some(),
            page_zoom: self.set_zoom_level.is_some(),
        }
    }
}

/// Pure planning function used by both production code and host tests.
pub fn plan_css_pixels(
    capabilities: CssPixelCapabilities,
    reported_density: f32,
) -> CssPixelReport {
    let density = if reported_density.is_finite() && (0.5..=4.0).contains(&reported_density) {
        reported_density
    } else {
        1.0
    };
    let complete_native = capabilities.w3c_css_pixels
        && capabilities.pixel_density
        && capabilities.full_content_zoom
        && capabilities.page_zoom;
    let mode = if complete_native {
        CssPixelMode::NativeLab126
    } else if capabilities.w3c_css_pixels || capabilities.pixel_density {
        CssPixelMode::NativePartial
    } else {
        CssPixelMode::StandardWebKit
    };
    let applied_zoom = if capabilities.pixel_density && capabilities.page_zoom {
        density
    } else {
        1.0
    };
    CssPixelReport {
        mode,
        reported_density: density,
        applied_zoom,
        capabilities,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn complete_lab126_stack_uses_device_density() {
        let capabilities = CssPixelCapabilities {
            w3c_css_pixels: true,
            pixel_density: true,
            full_content_zoom: true,
            page_zoom: true,
        };
        let report = plan_css_pixels(capabilities, 1.796_407_2);
        assert_eq!(report.mode, CssPixelMode::NativeLab126);
        assert!((report.applied_zoom - 1.796_407_2).abs() < 0.000_001);
    }

    #[test]
    fn standard_webkit_does_not_invent_a_viewport_or_zoom() {
        let report = plan_css_pixels(CssPixelCapabilities::default(), 1.796_407_2);
        assert_eq!(report.mode, CssPixelMode::StandardWebKit);
        assert_eq!(report.applied_zoom, 1.0);
    }

    #[test]
    fn invalid_density_is_rejected() {
        let capabilities = CssPixelCapabilities {
            pixel_density: true,
            page_zoom: true,
            ..Default::default()
        };
        let report = plan_css_pixels(capabilities, 99.0);
        assert_eq!(report.reported_density, 1.0);
        assert_eq!(report.applied_zoom, 1.0);
    }
}
