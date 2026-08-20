# Root-cause analysis: why RAnki cards render inconsistently on Kindle

## Executive finding

The dominant failure is not a single bad font size. RAnki mixes three independent coordinate systems:

- physical framebuffer pixels;
- GTK widget scaling;
- WebKit CSS/page zoom.

It then applies a text-only WebKit zoom by default. Images, CSS breakpoints, fixed dimensions, and typography therefore do not scale as one document. A global cap on that same zoom merely moves the error in the opposite direction.

## Evidence from pinned upstream RAnki

Pinned source: `crazy-electron/ranki@d671ee657f0c411474d2afff3bf9cbb49be2fb44`.

`views/base.vala` defines the GTK scale as:

```vala
get_screen().get_width() / 600.0
```

`views/review.vala` then configures the WebView with:

```vala
keyfile.get_double("General", "scale") * scaling
```

The current release package contains `scale=1.5`. With a 1264-pixel-wide PW6:

```text
GTK scale       = 1264 / 600 = 2.1067
requested zoom  = 1.5 × 2.1067 = 3.1600
```

This value is derived from physical width, not from the WebKit engine's logical CSS-pixel model.

RAnki also:

- creates a fresh complete HTML document for every question and every answer;
- calls `load_html_string()` on each side;
- injects card CSS into that temporary page;
- wraps rendered content in an additional `<div class="card kindle">`;
- does not apply the exact Anki `card cardN isLin` body-class contract;
- does not enable Kindle's native full-content zoom before setting zoom.

The reproducible audit is implemented in `tools/audit_ranki.py` and runs in CI against the pinned commit and release package.

## Why text and images diverge

WebKitGTK 1.x defines `full-content-zoom=FALSE` as the default. In that mode, `webkit_web_view_set_zoom_level()` changes text size rather than scaling every page element. This directly matches the real-device symptom: text can become enormous while an image remains comparatively small, and a later global zoom cap can make normal typography tiny without repairing responsive geometry.

## Evidence from the Kindle runtime

The official PW6 firmware oracle identifies:

- platform `Bellatrix4`;
- ARMv7 hard-float userspace;
- WebKitGTK 1.x runtime (`libwebkitgtk-1.0.so.0.7.2`);
- Amazon source baseline WebKitGTK 1.4.2 and GTK+ 2.20.1.

The shipped Mesquite browser imports Lab126 extensions including:

```text
webkit_web_view_set_useW3CStd_cssPixelsPerInch
webkit_web_view_get_pixel_density
webkit_web_view_set_full_content_zoom
webkit_web_view_set_fixed_layout
webkit_web_view_set_fixed_layout_width
webkit_web_view_set_fixed_layout_height
webkit_web_view_resize_view_to_content
webkit_web_view_render_partial
```

ARM call-site disassembly shows the native scale sequence:

```text
set_useW3CStd_cssPixelsPerInch(1)
density = get_pixel_density()
if density != 1:
    set_full_content_zoom(web_view, 1)
    set_zoom_level(web_view, density)
```

The first function is a global boolean setter; the density getter has no ordinary argument and returns a float. This is stronger evidence than an inferred `@media` breakpoint or a hand-selected zoom constant.

## Why the prior 1.25 cap also failed

The previous shim intercepted `webkit_web_view_set_zoom_level()` and constrained every request to `0.90–1.25`. This reduced the worst oversized-text cases, but it did not:

- enable W3C-standard CSS pixels;
- query the panel density;
- enable full-content zoom;
- reconstruct Anki's reviewer lifecycle.

The cap therefore removed much of the effective scale while leaving the coordinate-system mismatch intact. The user's second-round photographs—small text, small pictures, large unused page area—are the expected failure mode.

## Secondary incompatibilities

Even after native scaling is corrected, these differences remain material:

1. **Document lifetime** — Anki keeps one reviewer document and updates a persistent `#qa`; RAnki reloads the page on every side.
2. **Script lifecycle** — Anki explicitly recreates inserted `<script>` nodes so card scripts run. Raw `innerHTML` alone does not do this.
3. **Body classes** — templates may depend on `card1`, `card2`, etc.
4. **Extra `.card` ancestry** — an added wrapper can cause template rules to match twice or at the wrong level.
5. **AV tags** — desktop Anki handles replay metadata outside ordinary card HTML; RAnki/Kanki currently reconstruct controls differently.
6. **Typed answers and hints** — backend/template substitutions require explicit reviewer support; unsupported syntax can surface literally or yield blank fronts.
7. **Engine gap** — WebKitGTK 1.4-era CSS/JavaScript is far behind Chromium. The reviewer must supply targeted compatibility transforms, not silently redesign each deck.

## Corrective strategy

Kanki Next starts from the native renderer contract:

- call the Lab126 CSS-pixel sequence before/after creating the first WebView;
- never multiply WebView scale by GTK screen-width scaling;
- use full-content zoom so type, images, boxes, and breakpoints share one scale;
- keep one persistent `#qa` document;
- apply exact card/body classes;
- re-execute inserted scripts;
- record `innerWidth`, computed type size, image geometry, breakpoints, and runtime identity on the real device;
- introduce compatibility shims only for features the target WebKit demonstrably lacks.
