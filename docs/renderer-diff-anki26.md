# Kanki vs Anki 26.08 reviewer pipeline

This document records renderer differences that can change card layout even when both clients use the same Anki 26.08 backend and the same note type. It is intentionally deck-agnostic.

## Ground-truth references

Renderer decisions now use three first-class references:

1. **Anki 26.08 desktop source** — intended reviewer contract and browser-side lifecycle.
2. **Official Amazon PW6 firmware/rootfs + source bundles** — exact Kindle userspace/browser capabilities. See `docs/kindle-system-oracle.md`.
3. **Per-card Kanki diagnostics** — exact RAnki input HTML, exact Kanki-patched HTML and final WebKit computed layout.

The Kindle system is not treated as a generic “old ARM Linux browser”. The extracted PW6 runtime exposes Lab126-specific WebKit APIs such as `webkit_web_view_set_useW3CStd_cssPixelsPerInch`, `webkit_web_view_set_fixed_layout`, `webkit_web_view_resize_view_to_content`, `webkit_web_view_render_partial`, and the normal zoom/viewport calls. We should understand and use these native mechanisms before making synthetic media-query rewriting permanent.

## Reference paths

Anki 26.08:

- `qt/aqt/reviewer.py`
- `qt/aqt/webview.py`
- `qt/aqt/theme.py`
- `ts/reviewer/index.ts`
- `ts/reviewer/browser_selector.ts`
- `ts/reviewer/reviewer.scss`

RAnki upstream:

- `views/review.vala`

Kanki compatibility layer:

- `src/webkit_compat_shim.c`
- `src/anki_adaptive_v2.js`
- `src/anki_compat.js`
- `src/render_diagnostics.js`

## Rendering pipeline comparison

| Stage | Anki 26.08 desktop | RAnki/Kanki today | Layout consequence |
|---|---|---|---|
| Reviewer document lifetime | Creates one persistent reviewer page with `<div id="qa" dir="auto"></div>` | Rebuilds a complete HTML document for every question and every answer, then calls `webkit_web_view_load_html_string()` | Card JS state, fonts, image state and scroll lifecycle are reset on every side in Kanki |
| Card insertion | `_updateQA()` assigns `qa.innerHTML` and explicitly replaces every `<script>` so scripts execute | Rendered card HTML is already present when the new page loads | Script execution timing and DOM ancestry differ |
| Body classes | `_showQuestion()` sets `document.body.className` from `body_classes_for_card_ord()` -> `card cardN isLin/...` | Upstream RAnki wraps card HTML in `<div class="card kindle">`; Kanki later unwraps it and gives body `card isLin kindle` | Kanki currently lacks exact `cardN`, so note types that style `.card1`, `.card2`, etc. can differ |
| Browser/platform classes | `browser_selector.ts` adds `.mobile` only for iOS/Android user agents; desktop gets `.linux`, `.mac`, or `.win` | Kanki deliberately exposes Kindle as a compact/mobile environment and adds `.mobile .linux .kindle` | Decks with `.mobile` rules may use a different design from PC Anki |
| Browser engine | Qt WebEngine/Chromium | Kindle system WebKitGTK 1.x API with Lab126 extensions | CSS/JS support differs, but Kindle-specific native layout APIs may compensate for part of the gap |
| CSS custom properties | Native | Kanki resolves common `var(--x)` patterns before paint | Complex/nested CSS can still diverge from Chromium |
| CSS pixels / viewport | Chromium/Qt expose logical CSS geometry and apply app zoom | Kindle includes Lab126 W3C-CSS-pixel, fixed-layout, viewport and zoom APIs; Kanki currently also rewrites width breakpoints around an experimental 420px logical width | The 420px rewrite is a temporary heuristic and should be removed if the native API reproduces correct logical pixels |
| Reviewer baseline CSS | Official `reviewer.scss`: body margin 20px, image caps, list alignment, replay SVG 40x40 | Kanki mirrors this small baseline | Should be close; deck CSS still owns typography |
| Audio | Python extracts AV tags and `av_player` plays them outside card HTML | Kanki detects `[sound:...]`/`Audio()` in the page and bridges to Kindle audio | Audio controls can have different DOM than official Anki |
| MathJax | Persistent MathJax 3, `_updateQA()` waits for typesetting before showing | Upstream RAnki serves MathJax 2.7.9 and reloads it with each card document | Formula size/timing can differ |
| Answer scrolling | After images load, Anki scrolls `#answer` into view | Kanki currently reloads the answer page and normally starts at the top | Long-answer navigation differs |
| Inner `.card` container | Official body itself is `.card`; a template may also create its own visual container | RAnki adds an extra `.card kindle` wrapper around the template | The same `.card` CSS can be applied twice; Kanki v2 detects and neutralizes only the outer shell |

## Why upgrading the backend did not change layout

The Rust backend renders the card content and CSS, but the final layout is performed by the browser. Replacing Anki 25.09 with 26.08 upgrades scheduling, sync, collection and rendering services, but it does not replace Kindle's system WebKit with Chromium. Therefore a successful backend upgrade can leave the page looking identical.

## Diagnostic contract

Development builds enable renderer diagnostics unless a file named `disable-render-debug` is present in `/mnt/us/extensions/ranki/`.

For the first 40 WebKit document loads of each launch, Kanki writes:

- `render-debug/render-N-input.html` — exact complete HTML produced by upstream RAnki immediately before Kanki interception.
- `render-debug/render-N-patched.html` — exact complete HTML actually handed to WebKit after Kanki injection.
- `render-debug/render-N-meta.txt` — render id, base URI and byte sizes.
- `render-debug/00-system-fingerprint.txt` — actual Kindle firmware/runtime fingerprint, for matching against the extracted official rootfs.

`ranki.log` additionally receives structured lines:

- `KANKI_RENDER_NATIVE|...` — native interception/capture stage.
- `KANKI_RENDER|N|page|{...}` — viewport, user agent, platform/body classes, scroll geometry and transformation counters.
- `KANKI_RENDER|N|element|{...}` — computed font, line-height, box geometry, margins, padding, display/position and text preview for each visible element.
- `KANKI_RENDER|N|element-summary|{...}` — DOM/visible element counts.

Two computed-layout snapshots are recorded: `initial` shortly after DOM ready, and `settled` after card JS/images have had time to change geometry.

On the next launch, the previous session's HTML captures are moved to `render-debug.previous/` instead of being immediately discarded.

## Next compatibility milestones

1. Match the real-device fingerprint to the official PW6 rootfs before raising any binary/runtime assumption.
2. Trace Mesquite call sites for Lab126's CSS-pixel/fixed-layout/viewport APIs and determine their signatures/arguments.
3. Replace the experimental 420px media-query rewrite with Kindle's native CSS-pixel/DPI path if it reproduces Anki-like logical geometry.
4. Use capture data to identify whether a mismatch first appears in backend HTML, Kanki preprocessing, or WebKit computed layout.
5. Reproduce Anki's exact body class contract, especially `cardN`, using the queued card template ordinal instead of guessing from CSS.
6. Move toward a persistent `#qa` reviewer document so question/answer DOM and script lifecycle match Anki instead of rebuilding the whole page.
7. Move AV-tag handling closer to Anki's backend-driven `question_av_tags()/answer_av_tags()` model.
8. Match Anki's answer-scroll and image/MathJax timing behavior where it materially affects e-ink review.

The goal is not to invent a Kindle design for each deck. The target is: **same rendered card semantics as Anki 26.08, using the exact Kindle system as the browser/runtime oracle, with only the minimum compatibility substitutions actually required by that system.**
