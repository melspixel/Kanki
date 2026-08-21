# ADR 0003 — Package a pinned MathJax runtime in the persistent reviewer

- Status: Accepted
- Date: 2026-08-21
- Branch: `rewrite-v1`

## Context

The fixed Anki 26.08.1 backend preserves MathJax delimiters in rendered card HTML. Anki Desktop supplies a MathJax runtime in its reviewer, but Kanki's source-owned persistent WebView did not. As a result, correct backend output containing `\(...\)`, `\[...\]` or `math/tex` scripts remained unrendered on Kindle.

Formula support must work in the old Kindle WebKit without changing Anki rendering semantics, applying deck-specific CSS, reloading the reviewer, or treating every SVG as an audio icon. A release must also identify every redistributed renderer input.

## Decision

Kanki packages the official MathJax `2.7.9` npm distribution with SHA-256 `7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786` and its Apache-2.0 license. `tools/install_mathjax.sh` is the checksum-verifying source recipe; `tools/build_kindle_package.sh` is the only recipe that copies the verified runtime into the Kindle package.

The device reviewer loads MathJax once from `/mnt/us/extensions/kanki/assets/vendor/mathjax-2.7.9` with `TeX-AMS_SVG-full`. SVG output avoids reliance on MathJax webfonts in the Kindle firmware. Each question or answer is typeset only within the existing persistent `#qa` after card scripts and semantic AV markers have been installed.

The reviewer associates asynchronous typesetting completion with a monotonically increasing render generation. A callback from an older card cannot publish completion, diagnostics or UI state for a newer card. Existing MathJax state is removed before the same `#qa` receives new content. Scrolling, renderer diagnostics, native render completion and question/answer UI state are published only after typesetting finishes.

The runtime has no generic `svg` or `img` rewrite. Host contracts exercise real upstream SVG output and separately prove that an ordinary card SVG retains its dimensions. Package identity records the MathJax version and archive checksum, and `MANIFEST.sha256` covers every redistributed MathJax file.

RAnki remains reference-only. Its formula implementation may inform historical compatibility research, but no RAnki runtime, patch, asset or package path is used.

## Consequences

### Positive

- Formula semantics remain Anki-authored while Kanki supplies the missing reviewer capability.
- One persistent WebView and one persistent `#qa` serve every card side.
- Renderer completion cannot race ahead of formula layout.
- Formula SVG is distinguished by MathJax's own DOM, so ordinary SVG and images remain untouched.
- A candidate package identifies and manifests the exact formula runtime.

### Costs

- The installable archive grows because it includes the compatible MathJax 2 runtime and SVG jax.
- Host gates need network access on a cold cache and execute a real MathJax/jsdom contract.
- Kindle WebKit rendering and performance still require PW6 hardware evidence for the exact candidate SHA.

## Rejected alternatives

### Leave delimiters unrendered

Rejected because it knowingly diverges from Anki reviewer behavior.

### Render formulas in Kanki's Rust or C bridge

Rejected because it would duplicate Anki/reviewer semantics and create another card-rendering stack.

### Adopt MathJax 3 without an old-WebKit proof

Rejected for this baseline because the PW6 WebKit compatibility risk is higher. A future upgrade requires its own source pin, host contract and hardware evidence.

### Reuse RAnki's installed MathJax files

Rejected because the rewrite must install independently under `/mnt/us/extensions/kanki` and may not run, patch or package RAnki.

### Apply global SVG or formula CSS fixes

Rejected because global rules can corrupt ordinary card images, audio controls and note-template layout.

## Verification required

This decision is not PW6 acceptance. Issue #11 remains the closure record. The exact release candidate must still prove:

- checksum verification from a cold and warm cache;
- real MathJax inline/display SVG output in host gates;
- persistent `#qa`, stale-callback isolation and ordinary SVG/image preservation;
- ARMHF package identity, manifest and reproducible archive evidence;
- inline/display MathJax, cloze, long-card and ordinary SVG/image behavior in Kindle WebKit on PW6.
