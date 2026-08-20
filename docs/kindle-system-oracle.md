# Kindle system as a first-class Kanki reference

Kanki should not treat the Kindle as an unknown ARM Linux box. Amazon publishes official Kindle update packages, and the Kindle modding toolchain can extract their root filesystem images. For supported devices this gives us an exact userspace reference for the runtime Kanki must live inside.

This document defines how the extracted system is used without redistributing Amazon firmware bytes.

## Sources

Primary runtime source:

- Amazon official Kindle firmware update package for the target device.
- For PW6 / Paperwhite 12th Generation (2024), Amazon exposes a stable download redirect at `https://www.amazon.com/update_KindlePaperwhite_12th_Gen_2024`.
- KindleTool can extract the OTA package into its component images, including a compressed rootfs image.

Secondary source/reference:

- Amazon's Kindle Source Code Notice for open-source components.
- KindleModding/Kindle SDK and koxtoolchain for established extraction/sysroot conventions.

Kanki CI never uploads the firmware package, rootfs image, or proprietary libraries. It only uploads derived text inventories, ABI metadata, hashes and version reports.

## First observed PW6 system baseline

The first successful CI extraction used Amazon's PW6 update redirect. The extracted rootfs identified itself as **Kindle 5.19.6**, target OTA `4832160042`, platform `Bellatrix4`. Amazon's public software-update/source-code pages can lag a staged OTA redirect, so a real-device fingerprint remains the authority for the user's installed version.

Important renderer/runtime findings from that rootfs:

- ARMv7 hard-float userspace.
- glibc exposes symbols through **GLIBC_2.35**. This is substantially newer than the conservative ABI assumptions used during the first Anki 26.08 backend experiment; a real-device fingerprint must still confirm the user's installed firmware before we raise any binary requirement.
- Kindle still ships the legacy **WebKitGTK 1.x API**, with `libwebkitgtk-1.0.so.0.7.2`.
- Amazon's published PW6 source bundle for 5.19.5 contains `webkit-1.0_1.4.2.tar.gz`, identifying the upstream WebKit baseline as **WebKitGTK 1.4.2**, and `gtk+-2.0_2.20.1.tar.gz`.
- The runtime browser stack is intentionally mixed: GTK+ 2.20.1, GLib 2.72.3, old Pango ABI, newer ICU, and GStreamer 1.20.6 coexist around the old WebKit API.
- `/usr/bin/browser` advertises a legacy Kindle user agent containing `AppleWebKit/531.2+`, `Safari/533.2+` and `Kindle/3.0+`; therefore UA-based feature inference is unreliable.
- `/usr/bin/mesquite` links directly to `libwebkitgtk-1.0.so.0` and imports Amazon/Lab126 WebKit extensions not present in ordinary WebKitGTK, including:
  - `webkit_web_view_set_useW3CStd_cssPixelsPerInch`
  - `webkit_web_view_get_pixel_density`
  - `webkit_web_view_set_fixed_layout`
  - `webkit_web_view_set_fixed_layout_width`
  - `webkit_web_view_set_fixed_layout_height`
  - `webkit_web_view_resize_view_to_content`
  - `webkit_web_view_render_partial`
  - `webkit_web_view_set_full_content_zoom`
  - the normal WebKit zoom APIs.

These custom APIs are especially important. They show that Kindle already has native mechanisms for CSS-pixel/DPI handling, fixed layout and partial e-ink rendering. Kanki should use those mechanisms before relying on broad CSS/media-query rewriting.

## Mesquite call-site evidence

The firmware-oracle workflow now disassembles Mesquite and records call-site contexts rather than guessing API signatures from names.

The CSS-pixel path is particularly clear in ARM EABI:

```text
mov r0, #1
bl  webkit_web_view_set_useW3CStd_cssPixelsPerInch
bl  webkit_web_view_get_pixel_density
... compare returned float with 1.0 ...
ldr r0, [web_view]
mov r1, #1
bl  webkit_web_view_set_full_content_zoom
... returned pixel density in VFP s0 ...
ldr r0, [web_view]
bl  webkit_web_view_set_zoom_level
```

A false branch calls the W3C-CSS-pixel setter with `r0 == 0`. This strongly establishes that `webkit_web_view_set_useW3CStd_cssPixelsPerInch` is a **global boolean setter**, not a `(WebView*, bool)` function. `webkit_web_view_get_pixel_density` takes no ordinary argument and returns a float. When W3C-standard CSS pixels are enabled and density differs from 1, Mesquite enables full-content zoom and sets the web-view zoom level to the reported pixel density.

That sequence is much stronger evidence than Kanki's earlier assumption that a PW6 should be forced to an arbitrary ~420 CSS-pixel viewport. Mesquite's native sequence is now the reference implementation for Kanki's zoom/CSS-pixel path.

Fixed-layout signatures are also visible from call sites:

```text
r0 = web_view; r1 = 1;      webkit_web_view_set_fixed_layout(...)
r0 = web_view; r1 = width;  webkit_web_view_set_fixed_layout_width(...)
r0 = web_view; r1 = height; webkit_web_view_set_fixed_layout_height(...)
```

`webkit_web_view_resize_view_to_content` is called with only the web view in `r0`. `webkit_web_view_render_partial` is used together with Cairo and rectangle-like geometry for partial e-ink painting; it is an optimization candidate after basic reviewer equivalence is correct.

The first GStreamer inventory also confirmed the device-native audio path we observed experimentally: GStreamer 1.20.6 includes `mixersink`, `ttssrc`, `audioconvert`, `audioresample`, playback and ALSA plugins. It does **not** expose a normal desktop `wavparse` plugin in the extracted plugin set, which explains why the current Kanki audio bridge needed to avoid assuming a desktop GStreamer installation.

## CI system-oracle pipeline

`.github/workflows/audit-pw6-firmware.yml` performs the following:

1. Download the official Amazon PW6 firmware package.
2. Build KindleTool from the KindleModding SDK sources.
3. Extract the OTA package.
4. Decompress and mount the rootfs read-only.
5. Trace Mesquite imports and ARM call sites for Kindle-specific WebKit layout APIs.
6. Run `tools/audit_kindlerootfs.sh` over the mounted filesystem.
7. Upload only derived manifests/disassembly contexts.

The audit inventories:

- firmware/version files;
- ARM loader and glibc ABI;
- WebKitGTK and JavaScriptCore;
- GTK/GDK/GLib/libsoup;
- Pango/fontconfig/freetype/harfbuzz;
- GStreamer core and plugins;
- installed system fonts;
- browser/renderer executables;
- SHA-256 identities for relevant runtime libraries;
- ELF NEEDED/SONAME and GLIBC/GCC symbol-version requirements;
- Kindle-specific WebKit exported APIs and Mesquite renderer call sites.

`.github/workflows/audit-pw6-source.yml` separately downloads the official Amazon source-code bundle and scans renderer-related nested archives. It confirms the WebKitGTK 1.4.2 / GTK+ 2.20.1 source baselines. The Lab126-specific CSS-pixel/layout exports are evidenced by the shipped runtime binaries and Mesquite imports/call sites rather than by the stock WebKit source archive.

## Real-device matching

Development Kanki packages include `kindle-system-fingerprint.sh`. On startup it writes:

`/mnt/us/extensions/ranki/system-fingerprint.txt`

and, when renderer diagnostics are enabled, copies the same data to:

`/mnt/us/extensions/ranki/render-debug/00-system-fingerprint.txt`

The fingerprint intentionally contains only system/runtime information. It does not read account credentials, Wi-Fi configuration, serial numbers or user content.

It records the installed firmware/version hints, CPU/framebuffer information, loader/libc identities, relevant renderer library paths/hashes, GStreamer plugins and font inventory. We can then compare those hashes with the extracted official rootfs report and know whether the CI reference system actually matches the user's device.

## Why this matters for card rendering

A card's final appearance is the result of four different layers:

1. **Anki backend rendering** — produces rendered question/answer HTML, CSS and AV metadata.
2. **Reviewer runtime contract** — body classes, persistent `#qa`, script execution order, MathJax/image lifecycle, platform classes and replay controls.
3. **Browser engine/runtime** — on desktop Anki this is Qt WebEngine/Chromium; on Kindle/RAnki it is the system WebKitGTK/JavaScriptCore stack plus Lab126 extensions.
4. **Device presentation** — actual fonts, fontconfig, DPI/viewport behavior and e-ink screen.

The extracted Kindle rootfs gives us layer 3 and much of layer 4 exactly. Renderer work should therefore be based on observed capabilities of those exact libraries rather than guessed browser age or generic WebKit assumptions.

## Engineering rules going forward

- Prefer a native Kindle capability already present in the rootfs over bundling a replacement when practical and stable.
- Build/link compatibility checks against the actual target userspace ABI, not only a generic Debian ARM sysroot.
- Do not add deck-specific CSS to Kanki's renderer.
- When a card differs from desktop Anki, first locate the divergence among backend output, reviewer lifecycle, Kanki preprocessing and final WebKit computed style.
- Reproduce Mesquite's native W3C-CSS-pixel/pixel-density sequence before retaining any synthetic breakpoint rewrite.
- Use exact system font availability when deciding fallbacks.
- Use the actual GStreamer plugin inventory when selecting audio paths.
- Treat WebKit/JavaScriptCore feature support as measurable from the target system; maintain compatibility shims only for features the system really lacks.
- Keep firmware/rootfs bytes out of repository artifacts; derived manifests are sufficient for versioning and comparison.

## Next system-driven milestones

1. Match the real device fingerprint to the extracted PW6 rootfs before changing ABI assumptions.
2. Implement Mesquite's W3C-CSS-pixel + pixel-density + full-content-zoom sequence in an isolated renderer branch and measure `innerWidth`, computed font sizes and media-query matches.
3. Remove the current 420px media-query rewrite if the native sequence supplies correct logical CSS geometry.
4. Build a target sysroot overlay from the extracted rootfs for ABI/link verification of Kanki shims and Anki backend artifacts.
5. Reproduce Anki's persistent reviewer `#qa` lifecycle using only APIs supported by the system WebKit.
6. Test font selection using the actual Kindle fontconfig/fonts instead of desktop assumptions.
7. Use `render_partial` only after layout equivalence is established, to reduce full-screen e-ink refresh work.

The objective is not to make a generic Linux Anki port and hope it runs on Kindle. The objective is to make Kanki an Anki-compatible reviewer designed against the exact Kindle system it runs on.
