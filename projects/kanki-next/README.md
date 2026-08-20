# Kanki Next

Kanki Next is a clean-room reviewer rewrite for Kindle, built around Anki's real backend and the exact browser/runtime shipped by Amazon. It is not a collection of deck-specific CSS patches.

The first milestone is intentionally narrow: reproduce Kindle's native CSS-pixel and full-content-zoom sequence, run a persistent Anki-like reviewer document, and collect device measurements before the scheduler/sync UI is moved over.

## Current status

Implemented in this subproject:

- a small C module that resolves the Lab126 WebKitGTK extensions at runtime;
- the Mesquite-style W3C CSS-pixel → pixel-density → full-content-zoom → zoom sequence;
- a standalone GTK2/WebKitGTK1 renderer probe that runs on the PW6 userspace without build-time Kindle headers;
- an ES5-only persistent `#qa` reviewer shell with `cardN` body classes and script re-execution;
- host unit tests, static legacy-WebKit contract tests, ARMHF cross-build CI, packaging, and device-report collection;
- pinned upstream identities and a reproducible RAnki source/package audit.

Not yet implemented:

- the full deck browser and settings UI;
- the Anki 26.08 scheduler/sync adapter inside this executable;
- production AV-tag, MathJax, typed-answer, and answer-button integration;
- on-device acceptance results for every supported Kindle model.

## Why a rewrite is needed

Upstream RAnki computes a GTK scale from physical screen width and then multiplies it by a user scale for the WebView. On a 1264-pixel PW6 with the shipped `scale=1.5`, that requests roughly `3.16×` zoom. WebKitGTK 1.x defaults to text-only zoom, so fonts and replaced elements such as images do not share one physical scale. RAnki also rebuilds the entire HTML document for every question and answer and adds an extra `.card` wrapper, diverging from Anki's persistent reviewer lifecycle.

The earlier compatibility shim capped that zoom at `1.25×`. That prevented giant text but also removed the effective logical-pixel mapping, which is why ordinary card text and images became too small in the real-device photographs.

Amazon's own Mesquite browser uses Kindle-specific WebKit exports instead: enable W3C CSS pixels globally, read the panel pixel density, enable full-content zoom, and set zoom to that density. Kanki Next treats that sequence as the renderer baseline.

See [`docs/ROOT_CAUSE.md`](docs/ROOT_CAUSE.md) for the evidence chain.

## Local tests

```sh
make test
```

This generates the embedded probe page, compiles and runs the scale-state unit tests, checks the reviewer JavaScript/CSS against the supported legacy subset, parses the JavaScript with Node, and validates shell scripts.

## Device probe package

CI emits `kanki-next-render-probe.zip`. Extract its `kanki-next/` directory to:

```text
/mnt/us/extensions/kanki-next/
```

Launch **Kanki Next renderer probe** from KUAL. The probe shows reference type sizes, a deliberately large image, media-query state, and a question/answer transition inside one persistent WebView.

After exiting, run **Collect Kanki Next report** from KUAL. It writes:

```text
/mnt/us/documents/KankiNextProbeReport.txt
```

The report contains renderer geometry, runtime/library identities, and logs. It intentionally excludes account credentials, Wi-Fi configuration, serial numbers, and user documents.

## Repository layout

```text
projects/kanki-next/
├── src/                 native Kindle renderer foundation
├── web/                 persistent ES5 reviewer shell
├── tests/               host tests and compatibility gates
├── tools/               asset builder and upstream audit
├── scripts/             device launch/report helpers
├── package/             KUAL metadata and device README
├── evidence/            derived, redistributable audit summaries
└── docs/                architecture, root cause, test plan, handoff
```

## Engineering rule

When a card differs from desktop Anki, locate the first divergence among:

1. backend-rendered HTML/CSS/AV metadata;
2. reviewer DOM/lifecycle;
3. legacy WebKit parsing/computed layout;
4. Kindle DPI, fonts, and e-ink presentation.

Do not compensate with note-type-specific selectors until that boundary is known.
