# Release notes — 2026-08-22 (`build=93be8aa`)

This release is a substantial reviewer/launcher hardening pass over the preserved Diagnostic 1 baseline. The conclusions below are grounded in the uploaded package, its embedded `KANKI_BUILD.txt`, an unpacked-file hash comparison against Diagnostic 1, and source-readable CSS/JavaScript extracted from the new WebKit shim.

## Main changes

### 1. One readability policy across decks

The renderer no longer tries to hand-style a particular note type. It measures the card's substantial text and computes one type scale for the card.

Default launcher values:

- `KANKI_FLOOR_PX=24`
- `KANKI_CEILING_PX=56`
- `KANKI_MIN_CJK_PX=22`
- `KANKI_LINE_PERCENT=130`
- `KANKI_BLOCK_MAX_PX=12`
- `KANKI_ZOOM_PERCENT=100`

The embedded renderer weights font sizes by how much text they carry, so a small footnote cannot determine the scale for the whole card. The floor establishes readability; sizes carried beyond the ceiling can then be capped individually. CJK text has its own minimum because the glyphs carry more detail per em.

The renderer also caps excessive relative line-height and vertical block spacing, while retaining a deck's relative typography as far as possible.

### 2. Kindle-native display handling is integrated into the shim

The new ARMHF WebKit shim contains Kindle/Lab126 scale hooks for W3C CSS pixels, pixel density and full-content zoom. The reviewer shell explicitly anchors the root font at 16px and keeps page canvas/default text high-contrast for the greyscale display.

Other generic browser-compatibility work present in the embedded payload includes:

- width-media-query normalization around the Kindle logical reviewer width;
- fallback for unsupported modern flex/inline-flex display values;
- generic font-family fallbacks;
- viewport-measured image-height cap;
- nested `.card` shell normalization;
- 40×40 replay control bounds so template CSS cannot blow up the audio SVG;
- darkening of low-luminance text when it would collapse against a light e-ink background.

### 3. Long cards behave like pages rather than a drag surface

Long cards get a compact right-side pager only when the content actually overflows.

Defaults:

- `KANKI_PAGER_BOTTOM_PX=2`
- `KANKI_PAGE_OVERLAP_PX=80`

The pager shows up/down controls and a position indicator. Top/bottom tap zones provide an additional page-turn shortcut while preserving links, buttons, replay controls and other interactive elements.

### 4. On-device layout controls

A small gear is installed at the lower-left of the card view. The panel exposes the settings that can be changed at browser runtime:

- minimum font size;
- maximum font size;
- CJK minimum;
- line-height ceiling;
- vertical block spacing cap;
- page overlap.

The renderer attempts `localStorage` and also carries session overrides through `window.name`, so changes can survive card document replacement even on this old WebKit. Page zoom and rating-row height remain launcher-level settings because they are applied before card JavaScript runs.

### 5. More reading area for the reviewer

The launcher defaults `KANKI_BUTTON_HEIGHT_PX=72`. The new WebKit/GTK shim exports interception points around GTK builder/button handling so the over-tall Ranki rating row can be capped without affecting ordinary deck-list rows.

### 6. Diagnostics become opt-in

Normal review now writes to `/dev/null` by default instead of accumulating GTK/WebKit chatter indefinitely.

Create these sentinel files next to `ranki.sh` when needed:

- `enable-log` → collect `ranki.log`;
- `enable-render-debug` → enable per-render HTML/computed-layout diagnostics.

When render debugging is not enabled, old `render-debug/`, `render-debug.previous/`, and stale log output are removed. When enabled, the previous diagnostic capture is rotated and the first 40 loads can be retained.

### 7. Startup now takes over stale Ranki processes

The old duplicate-instance behavior is replaced by explicit cleanup.

At launch:

- stale `kanki-audio-*` / `kanki-gst-play*` helpers are killed immediately because they hold no persistent collection state;
- stale `ranki-arm*` reviewers receive a normal termination first so the collection can close cleanly;
- remaining reviewers are force-killed after a bounded wait;
- stale lock/PID files are removed before the new reviewer starts.

This addresses the failure mode where leaving full screen could leave an audio helper holding the loopback port and make the next launch look like a crash.

### 8. Config and firmware probes are less destructive/expensive

The package now ships `config.ini.default` rather than overwriting `config.ini`. A fresh install copies the default; an in-place update preserves the existing collection path and AnkiWeb key.

`kindle-system-fingerprint.sh` is included. The launcher caches the system fingerprint and GStreamer probe against a firmware stamp instead of recomputing them on every startup.

### 9. Backend rollback remains available

On ARMHF the launcher requests the external Anki 26.08 backend when both backend files are present. Creating `disable-anki26` forces the embedded RAnki 25.09 backend without reinstalling.

## Binary/file delta versus Diagnostic 1

Changed in the supplied release:

- `KANKI_BUILD.txt`
- `ranki.sh`
- `libkanki-webkit-armhf.so`
- `libkanki-webkit-armel.so`
- `libkanki-backend-redirect-armhf.so`
- `libanki-26.08-armhf.so`
- config packaging (`config.ini` → `config.ini.default`)
- new `kindle-system-fingerprint.sh`

Hash-identical to the preserved Diagnostic 1 package:

- `ranki-armhf`
- `ranki-armel`
- `kanki-audio-armhf`
- `kanki-audio-armel`
- `kanki-gst-play-armhf`
- `config.xml`
- `menu.json`
- `shortcut_ranki.sh`

The generated `dist/BINARY_DIFF_VS_DIAGNOSTIC1.tsv` records the exact sizes and SHA-256 values after materialization.
