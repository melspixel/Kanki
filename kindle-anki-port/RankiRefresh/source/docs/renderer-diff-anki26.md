# Kanki vs Anki 26.08 reviewer pipeline

This document records renderer differences that can change card layout even when both clients use the same Anki 26.08 backend and the same note type. It is intentionally deck-agnostic.

## Reference paths

Anki 26.08:

- `qt/aqt/reviewer.py`
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
| Browser engine | Qt WebEngine/Chromium | Legacy WebKitGTK | CSS variables, flex gap, newer JS, media queries, font handling and SVG behavior differ |
| CSS custom properties | Native | Kanki resolves common `var(--x)` patterns before paint | Complex/nested CSS can still diverge from Chromium |
| Width media queries | Chromium uses logical CSS pixels/device scale | Kindle WebKit exposes a high physical-looking width with DPR~1 | High-DPI Kindle can accidentally trigger desktop `min-width` rules; adaptive renderer rewrites them around a 420px logical viewport |
| Reviewer baseline CSS | Official `reviewer.scss`: body margin 20px, image caps, list alignment, replay SVG 40x40 | Kanki mirrors this small baseline | Should be close; deck CSS still owns typography |
| Audio | Python extracts AV tags and `av_player` plays them outside card HTML | Kanki detects `[sound:...]`/`Audio()` in the page and bridges to Kindle audio | Audio controls can have different DOM than official Anki |
| MathJax | Persistent MathJax 3, `_updateQA()` waits for typesetting before showing | Upstream RAnki serves MathJax 2.7.9 and reloads it with each card document | Formula size/timing can differ |
| Answer scrolling | After images load, Anki scrolls `#answer` into view | Kanki currently reloads the answer page and normally starts at the top | Long-answer navigation differs |
| Inner `.card` container | Official body itself is `.card`; a template may also create its own visual container | RAnki adds an extra `.card kindle` wrapper around the template | The same `.card` CSS can be applied twice; Kanki v2 detects and neutralizes only the outer shell |

## Why upgrading the backend did not change layout

The Rust backend renders the card content and CSS, but the final layout is performed by the browser. Replacing Anki 25.09 with 26.08 upgrades scheduling, sync, collection and rendering services, but it does not replace Kindle's legacy WebKitGTK with Chromium. Therefore a successful backend upgrade can leave the page looking identical.

## Diagnostic contract

Development builds enable renderer diagnostics unless a file named `disable-render-debug` is present in `/mnt/us/extensions/ranki/`.

For the first 40 WebKit document loads of each launch, Kanki writes:

- `render-debug/render-N-input.html` — exact complete HTML produced by upstream RAnki immediately before Kanki interception.
- `render-debug/render-N-patched.html` — exact complete HTML actually handed to WebKit after Kanki injection.
- `render-debug/render-N-meta.txt` — render id, base URI and byte sizes.

`ranki.log` additionally receives structured lines:

- `KANKI_RENDER_NATIVE|...` — native interception/capture stage.
- `KANKI_RENDER|N|page|{...}` — viewport, user agent, platform/body classes, scroll geometry and transformation counters.
- `KANKI_RENDER|N|element|{...}` — computed font, line-height, box geometry, margins, padding, display/position and text preview for each visible element.
- `KANKI_RENDER|N|element-summary|{...}` — DOM/visible element counts.

Two computed-layout snapshots are recorded: `initial` shortly after DOM ready, and `settled` after card JS/images have had time to change geometry.

On the next launch, the previous session's HTML captures are moved to `render-debug.previous/` instead of being immediately discarded.

## Next compatibility milestones

1. Use the new capture data to identify whether a mismatch first appears in backend HTML, Kanki preprocessing, or WebKit computed layout.
2. Reproduce Anki's exact body class contract, especially `cardN`, using the queued card template ordinal instead of guessing from CSS.
3. Decide from real card data whether Kindle should expose `.mobile` globally or whether logical viewport emulation alone is sufficient.
4. Move toward a persistent `#qa` reviewer document so question/answer DOM and script lifecycle match Anki instead of rebuilding the whole page.
5. Move AV-tag handling closer to Anki's backend-driven `question_av_tags()/answer_av_tags()` model.
6. Match Anki's answer-scroll and image/MathJax timing behavior where it materially affects e-ink review.

The goal is not to invent a Kindle design for each deck. The target is: **same rendered card semantics as Anki 26.08, with only the minimum compatibility substitutions required by legacy Kindle WebKit and e-ink input/output.**
