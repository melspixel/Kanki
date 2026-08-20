# Kanki Next architecture

## Objective

Deliver an Anki-compatible reviewer designed for the Kindle runtime, while preserving Anki's collection, scheduling, and sync semantics. The browser layer may degrade unsupported presentation features, but it must not invent deck-specific content or alter review scheduling.

## Layer model

### 1. Anki backend

Target: Anki 26.08 `rslib`, exposed through a narrow C ABI.

Responsibilities:

- collection open/close;
- sync and authentication;
- deck tree and search;
- scheduler queues and answer transitions;
- template rendering;
- AV-tag metadata;
- note/card mutations.

The existing `anki-26.08-backend` branch is the source for this layer. Kanki Next will consume it through a versioned adapter rather than calling unstable service numbers throughout the UI.

### 2. Native Kindle host

Technology: C/GTK2, dynamically resolved WebKitGTK1/Lab126 APIs.

Responsibilities:

- window and e-ink-friendly controls;
- one persistent WebView for the reviewer;
- exact native CSS-pixel/full-content-zoom setup;
- bridge backend events into reviewer JavaScript;
- receive reviewer actions and audio requests;
- crash-safe logs and device fingerprints;
- conservative refresh behavior.

The current milestone implements the scale module and renderer probe.

### 3. Reviewer document

Technology: HTML/CSS plus ES5 JavaScript.

Contract:

```html
<html class="linux kindle">
  <body class="card card1 isLin">
    <div id="qa" dir="auto"></div>
  </body>
</html>
```

Question and answer HTML are inserted into the same `#qa` node. Script elements are replaced so they execute. The answer side scrolls `#answer` into view when present. The document remains alive across sides and cards.

### 4. Compatibility transforms

Transforms are capability-based and observable. Examples:

- resolve simple CSS custom-property references before legacy WebKit parsing;
- provide a fallback for unsupported flex `gap`;
- convert backend AV metadata into replay controls;
- substitute typed-answer UI when the Kindle input contract is available;
- normalize unsupported modern JavaScript only when a safe transform exists.

Forbidden in the generic renderer:

- selectors naming a user's deck or note type;
- arbitrary global font sizes intended to make one deck look acceptable;
- fixed logical widths without a measured native API reason;
- swallowing template failures without diagnostics.

## Native scale state machine

The renderer resolves the following optional functions:

```text
set_useW3CStd_cssPixelsPerInch
get_pixel_density
set_full_content_zoom
set_zoom_level
```

Native path:

1. enable W3C CSS pixels globally before creating WebViews;
2. read density;
3. validate density within a defensive range;
4. enable full-content zoom when density differs from 1;
5. apply zoom equal to density.

Fallback path:

- if Lab126 functions are absent or return an invalid density, use full-content zoom at `1.0` when available;
- log the fallback status;
- do not synthesize `screenWidth/600` or a deck-specific constant.

Fixed layout is a separate, explicit API. Responsive Anki cards are not forced into fixed layout to hide a DPI bug.

## Process boundaries

Planned production split:

```text
kanki-next-ui
  ├── libanki backend adapter
  ├── persistent reviewer WebView
  ├── scheduler controls
  └── local IPC to audio helper

kanki-next-audio
  └── one-at-a-time local/remote media playback via Kindle audio stack
```

The renderer probe is deliberately independent of the Anki backend so native geometry can be validated before scheduler complexity is introduced.

## Data safety

- Collection paths remain under `/mnt/us`.
- Development packages do not embed AnkiWeb tokens.
- Device reports exclude serial numbers, account data, Wi-Fi settings, and user documents.
- Amazon firmware/source archives are never committed or redistributed; only hashes and derived text findings are retained.

## Milestones

### M0 — renderer oracle and probe

- native CSS-pixel sequence;
- persistent reviewer shell;
- device geometry report;
- CI cross-build and package.

### M1 — reviewer skeleton

- backend adapter opens a copied test collection;
- deck selection;
- question/answer rendering in persistent `#qa`;
- answer buttons and scheduler state transitions;
- no sync writes by default.

### M2 — compatibility surface

- AV metadata and audio;
- typed answers and hints;
- MathJax lifecycle;
- image-load/answer-scroll behavior;
- structured per-card diagnostics.

### M3 — sync-ready application

- authenticated sync;
- media sync;
- safe crash recovery and backup;
- settings and upgrade path;
- release acceptance matrix across supported Kindle models.
