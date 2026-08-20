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

## CI system-oracle pipeline

`.github/workflows/audit-pw6-firmware.yml` performs the following:

1. Download the official Amazon PW6 firmware package.
2. Build KindleTool from the KindleModding SDK sources.
3. Extract the OTA package.
4. Decompress and mount the rootfs read-only.
5. Run `tools/audit_kindlerootfs.sh` over the mounted filesystem.
6. Upload only derived manifests.

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
- ELF NEEDED/SONAME and GLIBC/GCC symbol-version requirements.

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
3. **Browser engine/runtime** — on desktop Anki this is Qt WebEngine/Chromium; on Kindle/RAnki it is the system WebKitGTK/JavaScriptCore stack.
4. **Device presentation** — actual fonts, fontconfig, DPI/viewport behavior and e-ink screen.

The extracted Kindle rootfs gives us layer 3 and much of layer 4 exactly. Renderer work should therefore be based on observed capabilities of those exact libraries rather than guessed browser age or generic WebKit assumptions.

## Engineering rules going forward

- Prefer a native Kindle capability already present in the rootfs over bundling a replacement when practical and stable.
- Build/link compatibility checks against the actual target userspace ABI, not only a generic Debian ARM sysroot.
- Do not add deck-specific CSS to Kanki's renderer.
- When a card differs from desktop Anki, first locate the divergence among backend output, reviewer lifecycle, Kanki preprocessing and final WebKit computed style.
- Use exact system font availability when deciding fallbacks.
- Use the actual GStreamer plugin inventory when selecting audio paths.
- Treat WebKit/JavaScriptCore feature support as measurable from the target system; maintain compatibility shims only for features the system really lacks.
- Keep firmware/rootfs bytes out of repository artifacts; derived manifests are sufficient for versioning and comparison.

## Next system-driven milestones

1. Match the real device fingerprint to the current official PW6 rootfs.
2. Record the exact WebKitGTK/JavaScriptCore/GTK versions and compile a feature matrix for CSS and JavaScript used by modern Anki card templates.
3. Build a target sysroot overlay from the extracted rootfs for ABI/link verification of Kanki shims and Anki backend artifacts.
4. Reproduce Anki's persistent reviewer `#qa` lifecycle using only APIs supported by the system WebKit.
5. Test font selection using the actual Kindle fontconfig/fonts instead of desktop assumptions.
6. Move audio and networking paths toward stable system components where the rootfs demonstrates they are available.

The objective is not to make a generic Linux Anki port and hope it runs on Kindle. The objective is to make Kanki an Anki-compatible reviewer designed against the exact Kindle system it runs on.
