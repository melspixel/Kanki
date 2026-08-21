# Rewrite status

**Branch:** `rewrite-v1`  
**Integration:** PR #10, Draft  
**Closure tracker:** issue #11  
**Release state:** implementation in progress; not yet hardware-accepted or release-installable  
**Target:** PW6 / ARMv7 hard-float  
**Checkpoint:** 2026-08-21

For zero-context takeover, read `docs/RESUME.md` first. For exact reviewer-semantic differences against pinned desktop Anki, read `docs/ANKI_DESKTOP_PARITY.md`.

## What is implemented on the branch

The rewrite is no longer only an architecture/bootstrap skeleton. The branch contains source-owned implementations for the major runtime paths:

- pinned Anki 26.08.1 production source core;
- RAnki retained only as a reference gitlink;
- semantic typed Anki review/deck/render bridge;
- semantic typed sync bridge;
- deterministic review-domain state machine;
- single persistent Anki-style `#qa` reviewer shell;
- exact `cardN` body-class protocol;
- deck/sync/reviewer device pages;
- generic old-WebKit CSS compatibility source/runtime;
- source-owned GTK2/WebKit Kindle application;
- Lab126/WebKit CSS-pixel/full-content-zoom feature-detection path;
- source-owned sync CLI/lifecycle separation;
- source-owned loopback audio service and pinned native `mixersink` helper;
- source-owned renderer diagnostics daemon on loopback `127.0.0.1:17393`;
- always-created/rotated `render-debug/` plus one previous-session directory;
- privacy-safe bounded geometry/style metrics;
- opt-in server- and client-bounded raw HTML/CSS/AV capture controlled by `enable-render-capture`;
- duplicate-instance/reactivation helper;
- mandatory build identity and manifest verification for launch and sync;
- redacted diagnostic-bundle script and Kindle-home report shortcut;
- handoff, architecture, install, test, desktop-parity and ADR documentation;
- host, Anki bridge, ARMHF, device, audio, CSS and package workflows.

Implementation presence is not the same as verification. Issue #11 remains the closure authority.

## Reproducibility/handoff work completed in this checkpoint

- Added `docs/RESUME.md` as a zero-context maintainer entry point.
- Expanded `docs/HANDOFF.md` into an operational handoff contract.
- Added `docs/ANKI_DESKTOP_PARITY.md` comparing reviewer semantics directly against the pinned Anki 26.08.1 desktop code.
- Added ADR 0002 for observability and reproducible device builds.
- Updated README/INSTALL/TESTING/issue #11/PR #10 to distinguish implemented from verified.
- Added `tools/run_host_gates.sh` as a one-command local host verification path.
- Added a minimal GitHub Actions runner probe to separate CI infrastructure failures from product failures.
- Replaced floating KindleHF `latest` downloads with checksum-pinned koxtoolchain `2026.08` (`kindlehf.tar.zst`, SHA-256 `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`).
- Added `tools/install_kindlehf_toolchain.sh` and made CI/package workflows use it.
- Added koxtoolchain identity to `BUILD.json` generation and third-party notices.
- Corrected the package recipe so `kanki-report.sh`, `kanki-diag` and renderer diagnostic runtime assets are actually included.
- Added renderer diagnostics contract tests and server-side storage/rate bounds.
- Removed repeated idle gap-layout work from the old-WebKit CSS runtime; compatibility layout is event/change driven rather than reapplied every 100 ms when nothing changed.

None of the above is marked verified on the latest commit until runners execute real steps.

## Verification already achieved during development

Earlier commits/iterations established useful component-level evidence for parts of the rewrite, including:

- Rust review state-machine behavior;
- persistent reviewer/`#qa` contract;
- card body class protocol;
- question/answer/rating flow contracts;
- replay SVG isolation from unrelated SVG;
- ARMHF native-device/audio helper compilation in individual iterations;
- parts of the typed Anki integration;
- generic CSS compatibility tests in individual iterations.

These results are engineering evidence, but they do **not** close the current candidate because later behavior-changing commits landed afterward. The release candidate must be revalidated on one exact commit.

## Current blocker — isolated from product source

At PR head `0a0822ce751cc18baa57dbd268df9a7f2be0f1d2`, minimal **Actions runner probe** run `32472150633`, job `96741001992`, completed `failure` with `steps = null`. All seven normal workflows triggered from the same head also completed `failure` before useful execution.

The probe contains no Kanki build dependencies and only requests an `ubuntu-latest` runner with a trivial shell step. This isolates the immediate blocker to GitHub Actions job execution/runner/account/repository infrastructure, not to a Kanki compiler/test failure.

Until the probe enters its first real step, do not change product source merely because these zero-step runs are red.

## Desktop Anki parity findings that remain open

A direct source audit against pinned `qt/aqt/reviewer.py` and `qt/aqt/theme.py` found several semantic items that must be closed before release:

- typed-answer `{{FrontSide}}` separator placement in the current bridge is not yet desktop-equivalent;
- card autoplay is currently inferred too aggressively from the presence of AV tags instead of coming from Anki card semantics;
- desktop can replay question audio on the answer side depending on card/deck settings, while the current packet exposes answer tags only;
- the native rating bar currently allocates four buttons unconditionally, while desktop scheduling can present 2/3/4 logical ratings;
- Lab126 CSS-pixel configuration is currently reviewer-entry-oriented and should be verified/moved to the WebView lifecycle boundary;
- ordinary HTTP(S) links from card HTML need an explicit policy so they cannot silently replace the persistent reviewer document.

These are documented in `docs/ANKI_DESKTOP_PARITY.md`; do not hide them behind visual CSS fixes.

## Renderer diagnostics behavior now designed into the rewrite

Normal launches create a fresh:

```text
/mnt/us/extensions/kanki/render-debug/
```

and retain at most one previous session at:

```text
/mnt/us/extensions/kanki/render-debug.previous/
```

Default metrics contain identifiers, side, body class, viewport/document geometry, DPR and bounded computed font/display/geometry information, but no element text. Client and server both bound the amount of diagnostic data. The standard redacted report may include current and previous metrics.

Raw HTML/CSS/AV capture is off by default because it can contain note content. It is enabled only by the sentinel:

```text
/mnt/us/extensions/kanki/enable-render-capture
```

Raw capture is bounded to the first 12 render sides and an 8 MiB server-side session cap. It is never included automatically in the redacted report. Diagnostic startup/directory failure is a launcher error rather than a silently ignored condition.

## What is not yet verified/closed

The following still require same-commit evidence before release:

- host workspace fmt/clippy/unit/integration suite on the final candidate;
- disposable Anki collection open/deck/queue/render/AV/answer/bury/reopen suite;
- normal sync, full-sync decision paths and media-sync lifecycle;
- ARMHF typed Anki library build and ABI audit;
- native Kindle shell and Lab126 CSS-pixel behavior on the candidate;
- `kanki-diag` ARMHF build, launch and bounded metric/capture behavior;
- complete generic CSS compatibility corpus;
- renderer parity corpus including type-answer, autoplay/replay semantics, rating-cardinality cases and original representative APKG decks without modification;
- reproducible installable package and manifest verification;
- clean-install / historical-upgrade / rollback tests;
- PW6 deck/review/audio/sync/scroll/lifecycle acceptance;
- diagnostic privacy review;
- maintainer reproduction from repository documentation alone.

## Immediate next actions

1. Restore GitHub-hosted Actions execution at the repository/account level; rerun the minimal probe first.
2. Do not edit product/workflow build logic in response to a zero-step failure.
3. While Actions is blocked, continue source-level parity audit and record/fix deterministic semantic differences that can be proven from the pinned Anki/Kindle source.
4. Once the probe executes, fix only the first real failing step in the narrowest workflow.
5. Establish one green host commit, then typed Anki host bridge, ARMHF bridge/device/audio/CSS/diagnostics, then package.
6. Freeze the first complete candidate only after all non-hardware gates are green on the same SHA.
7. Produce the first rewrite installable ZIP from the package workflow, not manually.
8. Run PW6 hardware acceptance, including the new automatic renderer metrics and opt-in raw capture if required.
9. Feed acceptance evidence back into issue #11 and update handoff/status before every handoff.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until Gate E in `docs/TESTING.md` is completed on the target PW6 against the exact release artifact.
