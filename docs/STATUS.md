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

## Current blocker — confirmed on newest handoff head

After the handoff documentation refresh, PR #10 advanced to a new head and all seven PR workflows again terminated as `failure` before executing useful steps. `Rewrite CI` run `32468549202` reports jobs `host` and `arm-skeleton`, both completed `failure`, with `steps = null`.

This reproduces the prior behavior on a fresh commit and strongly isolates the immediate blocker to GitHub Actions job execution/runner/account/repository infrastructure rather than a product source compile failure.

Until a job actually enters checkout/step 1, do not change Kanki source merely because these zero-step runs are red.

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

1. Diagnose why GitHub Actions creates jobs with no step list on this private repository/account.
2. Do not edit seven product/workflow files in parallel; first make one minimal workflow execute checkout successfully.
3. Once a runner executes, fix only the first real failing step in the narrowest workflow.
4. Establish one green host commit, then typed Anki host bridge, ARMHF bridge/device/audio/CSS, then package.
5. Freeze the first complete candidate only after all non-hardware gates are green on the same SHA.
6. Produce the first rewrite installable ZIP from the package workflow, not manually.
7. Run PW6 hardware acceptance and feed its diagnostic bundle back into issue #11.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until Gate E in `docs/TESTING.md` is completed on the target PW6 against the exact release artifact.