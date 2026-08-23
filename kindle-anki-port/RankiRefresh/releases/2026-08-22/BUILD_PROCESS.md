# Build/process reconstruction — RankiRefresh 2026-08-22

This document organizes the engineering path visible in the final release artifact. It distinguishes observed facts from reconstruction and does not claim access to the missing original `93be8aa` source commit.

## 1. Starting point

The preserved source lineage is Diagnostic 1:

- source CI merge: `f178e5e59e001bbf4964760d722fd6b9b10a28f1`
- exact source tree: `8fb4d25339660e1b82a984f666b2e54d7a45defa`
- Anki 26.08 backend experiment already existed and was known to run on Kindle ARMHF.

That complete source tree is mounted in this release directory as `source-base/`.

## 2. Renderer iterations visible in the final artifact

The 2026-08-22 WebKit shim is much larger than Diagnostic 1 (`86,200` bytes vs `36,800` bytes on ARMHF) and embeds a substantially expanded renderer runtime.

The final runtime shows the following sequence of work:

1. **Normalize Kindle browser geometry and defaults**
   - anchor root font size to 16px;
   - use Kindle/Lab126 W3C CSS-pixel/pixel-density/full-content-zoom hooks from the native shim;
   - keep the page canvas white and default text black for e-ink contrast.

2. **Retain generic old-WebKit compatibility**
   - resolve selected CSS variables/calculations;
   - rewrite wide-screen media-query behavior for the Kindle reviewer;
   - replace unsupported modern flex/inline-flex display modes with old-WebKit-safe boxes;
   - add generic font fallbacks;
   - normalize Ranki's extra card wrapper;
   - constrain replay SVG size.

3. **Measure actual rendered type instead of styling note types**
   - count text length at each computed font size;
   - choose substantial low/high anchors using text weight thresholds;
   - derive a single scale from the configured floor/ceiling;
   - scale absolute `px` declarations and the root font;
   - enforce a CJK floor where necessary;
   - cap outliers that exceed the ceiling after the lift.

4. **Compact monitor-oriented spacing**
   - cap excessive relative line height;
   - cap large vertical margins/padding;
   - add a measured image-height cap for a WebKit without usable `vh` behavior.

5. **Make long cards page-oriented**
   - calculate scroll/page geometry;
   - provide up/down page controls and position state only for overflow cards;
   - preserve page overlap;
   - add top/bottom tap regions while ignoring interactive card controls.

6. **Add an on-device settings layer**
   - bottom-left gear button;
   - runtime controls for floor, ceiling, CJK minimum, line-height cap, block spacing cap and page overlap;
   - localStorage when available;
   - `window.name` as a session carry mechanism across full-document card reloads.

## 3. Launcher hardening visible in `ranki.sh`

The final launcher changed from a duplicate-instance guard to explicit process takeover:

1. scan `/proc/*/comm` with shell builtins;
2. kill stale audio/GStreamer helpers immediately;
3. ask stale reviewers to terminate normally so the open collection can close;
4. wait a bounded interval;
5. force-kill only reviewers that remain;
6. clear stale PID/lock files;
7. create the new launch lock.

The implementation deliberately avoids spawning `tr` once per process because that cost seconds on the Kindle CPU.

## 4. Configuration and tuning defaults

The final launcher exports:

```text
KANKI_ZOOM_PERCENT=100
KANKI_FLOOR_PX=24
KANKI_CEILING_PX=56
KANKI_MIN_CJK_PX=22
KANKI_LINE_PERCENT=130
KANKI_BLOCK_MAX_PX=12
KANKI_PAGER_BOTTOM_PX=2
KANKI_PAGE_OVERLAP_PX=80
KANKI_BUTTON_HEIGHT_PX=72
```

`config.ini` is no longer supplied as the update payload. The package contains `config.ini.default`; a real `config.ini` is created only on a fresh install, preserving AnkiWeb credentials/path settings during updates.

## 5. Diagnostics and startup-cost cleanup

Diagnostics moved from development-default to explicit opt-in:

- no sentinel → output goes to `/dev/null`;
- `enable-log` → `ranki.log` is collected;
- `enable-render-debug` → render HTML/layout capture is enabled and the previous capture is rotated.

When diagnostics are disabled, stale debug directories/logs are removed.

The system fingerprint and GStreamer probe are cached against `/etc/version.txt`; they are recomputed only when the firmware stamp changes.

## 6. Audio and backend continuity

The native audio helper/player binaries in this release are SHA-256-identical to Diagnostic 1. The launcher still starts the audio server, records its PID, and cleans it up on exit.

ARMHF still prefers the external Anki 26.08 backend when available. `disable-anki26` remains the rollback switch to the embedded Ranki 25.09 backend.

The release carries a different `libanki-26.08-armhf.so` binary from Diagnostic 1. The binary identifies itself as Anki 26.08 and requires no newer than GLIBC 2.18/GCC 4.3.0, but the uploaded artifact does not embed a resolvable Anki source commit. The release record therefore preserves the binary hash rather than inventing a source pin.

## 7. Packaging observed in the supplied ZIP

The final install root is `ranki/` with 16 files:

```text
KANKI_BUILD.txt
config.ini.default
config.xml
kanki-audio-armel
kanki-audio-armhf
kanki-gst-play-armhf
kindle-system-fingerprint.sh
libanki-26.08-armhf.so
libkanki-backend-redirect-armhf.so
libkanki-webkit-armel.so
libkanki-webkit-armhf.so
menu.json
ranki-armel
ranki-armhf
ranki.sh
shortcut_ranki.sh
```

The package does not include user collection data or an existing `config.ini`.

## 8. Publication procedure used for this archive

1. Verify the uploaded release against the user-supplied SHA-256.
2. Upload the original ZIP/checksum to the existing Google Drive turnover folder `GPT周转/RankiRefresh`.
3. Publish a versioned GitHub release directory instead of overwriting Diagnostic 1 history.
4. Download the public Drive artifact inside GitHub Actions.
5. Verify the SHA-256 again on the runner.
6. Commit both the install ZIP and the complete unpacked `ranki/` runtime tree.
7. Extract the exact embedded reviewer CSS/JavaScript symbols from `libkanki-webkit-armhf.so` into `recovered-source/`.
8. Generate file hashes, ABI audit and a binary diff versus Diagnostic 1.
9. Fast-forward the canonical `kindle-anki-port` branch only after materialization succeeds.

This preserves both a human-readable development story and the actual bytes that shipped.
