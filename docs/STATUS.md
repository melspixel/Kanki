# Rewrite status

**Branch:** `rewrite-v1`  
**Integration:** PR #10, Draft  
**Closure tracker:** issue #11  
**Release state:** implementation in progress; not yet hardware-accepted or release-installable  
**Target:** PW6 / ARMv7 hard-float  
**Checkpoint:** 2026-08-21

For zero-context takeover, read `docs/RESUME.md` first.

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
- always-created `render-debug/` directory with privacy-safe geometry/style metrics;
- opt-in bounded raw HTML/CSS/AV capture controlled by `enable-render-capture`;
- duplicate-instance/reactivation helper;
- build identity, manifest-oriented packaging and rollback boundaries;
- redacted diagnostic-bundle script and Kindle-home report shortcut;
- handoff, architecture, install, test and ADR documentation;
- host, Anki bridge, ARMHF, device, audio, CSS and package workflows.

Implementation presence is not the same as verification. Issue #11 remains the closure authority.

## Reproducibility/handoff work completed in this checkpoint

- Added `docs/RESUME.md` as a zero-context maintainer entry point.
- Expanded `docs/HANDOFF.md` into an operational handoff contract.
- Updated README/INSTALL/issue #11/PR #10 to distinguish implemented from verified.
- Added a minimal GitHub Actions runner probe to separate CI infrastructure failures from product failures.
- Replaced floating KindleHF `latest` downloads with checksum-pinned koxtoolchain `2026.08` (`kindlehf.tar.zst`, SHA-256 `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`).
- Added `tools/install_kindlehf_toolchain.sh` and made CI/package workflows use it.
- Added koxtoolchain identity to `BUILD.json` generation and third-party notices.
- Corrected the package recipe so `kanki-report.sh`, `kanki-diag` and renderer diagnostic runtime assets are actually included.
- Removed repeated idle gap-layout work from the old-WebKit CSS runtime; compatibility layout is now event/change driven rather than reapplied every 100 ms when nothing changed.

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

The zero-step Actions failure remains reproducible after the latest source/documentation work. On PR head `85b1f62ab9e8e5630f9b1a9d64ea0639275c9ead`, minimal **Actions runner probe** run `32470385718`, job `96735736090`, completed `failure` with `steps = null`. All normal workflows failed in the same pre-step manner.

The probe contains no Kanki build dependencies and only requests an `ubuntu-latest` runner with a trivial shell step. This isolates the immediate blocker to GitHub Actions job execution/runner/account/repository infrastructure, not to a Kanki compiler/test failure.

Until the probe enters its first real step, do not change product source merely because these zero-step runs are red.

## Renderer diagnostics behavior now designed into the rewrite

Normal launches must create:

```text
/mnt/us/extensions/kanki/render-debug/
```

Default metrics contain identifiers, side, body class, viewport/document geometry, DPR and bounded computed font/display/geometry information, but no element text. The standard report may include these metrics.

Raw HTML/CSS/AV capture is off by default because it can contain note content. It is enabled only by the sentinel:

```text
/mnt/us/extensions/kanki/enable-render-capture
```

Raw capture is bounded to the first 12 renders and is never included automatically in the redacted report. Diagnostic startup/directory failure is a launcher error rather than a silently ignored condition.

## What is not yet verified/closed

The following still require same-commit evidence before release:

- host workspace fmt/clippy/unit/integration suite on the final candidate;
- disposable Anki collection open/deck/queue/render/AV/answer/bury/reopen suite;
- normal sync, full-sync decision paths and media-sync lifecycle;
- ARMHF typed Anki library build and ABI audit;
- native Kindle shell and Lab126 CSS-pixel behavior on the candidate;
- `kanki-diag` ARMHF build, launch and bounded metric/capture behavior;
- complete generic CSS compatibility corpus;
- renderer parity corpus including original representative APKG decks without modification;
- reproducible installable package and manifest verification;
- clean-install / historical-upgrade / rollback tests;
- PW6 deck/review/audio/sync/scroll/lifecycle acceptance;
- diagnostic privacy review;
- maintainer reproduction from repository documentation alone.

## Immediate next actions

1. Restore GitHub-hosted Actions execution at the repository/account level; rerun the minimal probe first.
2. Do not edit product/workflow build logic in response to a zero-step failure.
3. Once the probe executes, fix only the first real failing step in the narrowest workflow.
4. Establish one green host commit, then typed Anki host bridge, ARMHF bridge/device/audio/CSS/diagnostics, then package.
5. Freeze the first complete candidate only after all non-hardware gates are green on the same SHA.
6. Produce the first rewrite installable ZIP from the package workflow, not manually.
7. Run PW6 hardware acceptance, including the new automatic renderer metrics and opt-in raw capture if required.
8. Feed acceptance evidence back into issue #11 and update handoff/status before every handoff.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until Gate E in `docs/TESTING.md` is completed on the target PW6 against the exact release artifact.
