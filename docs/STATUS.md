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
- duplicate-instance/reactivation helper;
- build identity, manifest-oriented packaging and rollback boundaries;
- redacted diagnostic-bundle script and Kindle-home report shortcut;
- handoff, architecture, install, test and ADR documentation;
- host, Anki bridge, ARMHF, device, audio, CSS and package workflows.

Implementation presence is not the same as verification. Issue #11 remains the closure authority.

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

## Current blocker

At the last observed PR head before this documentation refresh, every PR-triggered workflow completed as `failure` within seconds and the jobs exposed no executed step list. Example `Rewrite CI` jobs (`host`, `arm-skeleton`) contained zero steps.

Working diagnosis: GitHub Actions execution/runner infrastructure is currently blocking useful CI execution. Until a job actually enters checkout/step 1, do not treat these zero-step failures as application/compiler failures.

This blocker is now documented in `docs/RESUME.md` so a new maintainer does not waste time shotgun-editing source or all workflow files in response to infrastructure-only red runs.

## What is not yet verified/closed

The following still require same-commit evidence before release:

- host workspace fmt/clippy/unit/integration suite on the final candidate;
- disposable Anki collection open/deck/queue/render/AV/answer/bury/reopen suite;
- normal sync, full-sync decision paths and media-sync lifecycle;
- ARMHF typed Anki library build and ABI audit;
- native Kindle shell and Lab126 CSS-pixel behavior on the candidate;
- complete generic CSS compatibility corpus;
- renderer parity corpus including original representative APKG decks without modification;
- reproducible installable package and manifest verification;
- clean-install / historical-upgrade / rollback tests;
- PW6 deck/review/audio/sync/scroll/lifecycle acceptance;
- diagnostic privacy review;
- maintainer reproduction from repository documentation alone.

## Immediate next actions

1. Re-check GitHub Actions on the newest `rewrite-v1` head after the handoff/status commits.
2. Confirm whether jobs execute real steps.
3. If they still fail with zero steps, diagnose Actions/account/repository execution before modifying product code.
4. Once runners execute, fix only the first real failing step in the narrowest workflow.
5. Establish one green host commit, then typed Anki host bridge, ARMHF bridge/device/audio/CSS, then package.
6. Freeze the first complete candidate only after all non-hardware gates are green on the same SHA.
7. Produce the first rewrite installable ZIP from the package workflow, not manually.
8. Run PW6 hardware acceptance and feed its diagnostic bundle back into issue #11.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until Gate E in `docs/TESTING.md` is completed on the target PW6 against the exact release artifact.