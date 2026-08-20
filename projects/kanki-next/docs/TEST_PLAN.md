# Test plan

## Test layers

### A. Host unit tests

`tests/test_scale.c` verifies:

- exact native call order;
- density `1.0` path;
- invalid-density fallback;
- missing-Lab126-API fallback;
- fatal missing standard zoom API;
- fixed layout remains explicit;
- raw reported density is preserved independently of applied zoom.

### B. Static legacy-engine contract

`tests/test_probe_contract.py` rejects constructs outside the current compatibility baseline:

- ES2015 arrow functions, `const`, `let`, classes, template strings, Promises;
- CSS Grid, CSS custom properties, and `clamp()`;
- multiple or missing persistent `#qa` roots;
- missing viewport metadata;
- missing `cardN` body classes or script re-execution;
- unresolved embedded-asset placeholders.

Node parses the JavaScript as a second syntax gate. Shell scripts are checked with `sh -n`.

### C. Upstream provenance audit

CI clones the pinned RAnki commit and asserts that the source features behind the diagnosis are still present. It downloads the release package and verifies the recorded ARM binary hashes. A changed upstream package must update `upstream.lock` and the root-cause report deliberately.

The official Kindle firmware/source audits remain separate workflows because they are large and must not publish proprietary bytes. Kanki Next consumes their derived reports and pinned hashes.

### D. ARMHF build and ABI audit

CI uses KindleHF koxtoolchain to build the probe and records:

- ELF class, architecture, and interpreter;
- dynamic dependencies;
- imported GLIBC symbol versions;
- required WebKit/Lab126 symbols resolved dynamically rather than at link time;
- package SHA-256.

The maximum required GLIBC version must not exceed the pinned PW6 oracle baseline.

### E. PW6 device acceptance

Run `kanki-next-render-probe.zip` on the actual Kindle and collect `KankiNextProbeReport.txt`.

Pass criteria for the native path:

1. `has_w3c_css_pixels=1`;
2. `has_pixel_density=1`;
3. `has_full_content_zoom=1`;
4. scale status is native;
5. reported density is plausible and matches applied zoom;
6. `innerWidth` is a compact logical width rather than the full physical framebuffer width;
7. the `max-width:420px` marker is active and the `min-width:800px` marker is inactive;
8. 24–32px reference text is comfortably readable at normal distance;
9. the probe image occupies most of the card width and scales with the document;
10. question→answer transition occurs without rebuilding the native WebView;
11. no GTK/GLib/WebKit diagnostics are painted onto the screen;
12. exit returns cleanly to KUAL/Kindle UI.

### F. Regression deck matrix (after M1)

Each supported release must exercise:

- short single-word card;
- long dictionary definition;
- image-heavy card;
- long list/table card;
- multiple card templates using `card1/card2` selectors;
- local audio and remote pronunciation;
- typed-answer template;
- hint template;
- MathJax inline and display formula;
- CJK and Latin mixed text;
- dark/background-heavy custom template;
- deliberately modern unsupported template, with a clear diagnostic rather than a blank page.

For each card capture:

- backend-rendered HTML/CSS/AV metadata;
- reviewer payload;
- final DOM and computed geometry;
- screenshot/photo;
- navigation and audio result.

## Release gate

A release candidate is not accepted from desktop screenshots alone. It requires the host/CI gates plus at least one matching real-device fingerprint and completed device acceptance report.
