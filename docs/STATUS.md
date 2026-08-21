# Rewrite status

**Branch:** `rewrite-v1`  
**Integration:** PR #10, Draft  
**Closure tracker:** issue #11  
**Release state:** implementation in progress; not yet PW6-accepted  
**Target:** PW6 / ARMv7 hard-float  
**Checkpoint:** 2026-08-21

For zero-context takeover, read `docs/RESUME.md` first. For desktop reviewer semantics read `docs/ANKI_DESKTOP_PARITY.md`. For builds outside GitHub Actions read `docs/LOCAL_BUILD.md`.

## What is implemented

The branch contains source-owned implementations for the major runtime paths:

- pinned Anki 26.08.1 production source core;
- RAnki retained only as a reference gitlink;
- semantic typed Anki review/deck/render bridge;
- semantic typed sync bridge;
- deterministic review-domain state machine;
- persistent Anki-style `#qa` reviewer shell with exact `cardN` classes;
- generic deck-agnostic old-WebKit compatibility;
- source-owned GTK2/WebKit Kindle application;
- Lab126/WebKit CSS-pixel/full-content-zoom feature path;
- source-owned sync lifecycle;
- source-owned loopback audio service and pinned `mixersink` player helper;
- deck-config-driven autoplay and answer-side question-audio replay path;
- source-owned renderer diagnostics daemon on `127.0.0.1:17393`;
- bounded privacy-safe renderer metrics and explicit bounded raw capture opt-in;
- duplicate-instance/reactivation helper;
- build identity, manifest verification, rollback/data boundaries;
- redacted diagnostic report path;
- host/bridge/ARM/device/audio/CSS/package workflows and handoff docs.

Implementation presence is not the same as verification. Issue #11 remains the closure authority.

## New local build path — GitHub Actions is no longer a compilation single point of failure

The canonical ARMHF package recipe is now:

```text
tools/build_kindle_package.sh
```

GitHub Actions and local builds both invoke this script. `.github/workflows/package.yml` no longer embeds a separate compile/package recipe.

Added:

- `tools/build_kindle_package.sh` — canonical pinned build, package, manifest, exported-symbol and GLIBC gates;
- `tools/local-builder.Dockerfile` — Ubuntu 24.04 + Rust 1.92.0 builder;
- `tools/local_package_docker.sh` — one-command local macOS/Linux executor;
- `docs/LOCAL_BUILD.md` — local build/evidence procedure.

On a developer Mac/Linux machine with Docker/OrbStack/Colima:

```sh
git checkout rewrite-v1
git pull --ff-only
git submodule update --init third_party/anki third_party/kindle-sdk third_party/audiobook-koplugin third_party/ranki-reference
bash tools/local_package_docker.sh
```

The wrapper forces `linux/amd64` by default because the pinned KindleHF toolchain is Linux x86-64-hosted. Apple Silicon uses Docker-compatible amd64 emulation. Cargo and KindleHF downloads are cached in named volumes.

Expected successful output:

```text
out/local-kindle/Kanki-rewrite-hw3.zip
out/local-kindle/Kanki-rewrite-hw3.zip.sha256
out/local-kindle/package-contents.txt
out/local-kindle/package-exports.txt
out/local-kindle/package-glibc.txt
out/local-kindle/sysroot-glibc.txt
out/local-kindle/toolchain-info.txt
```

The canonical script refuses a dirty root checkout by default, validates source pins, restores temporary Anki bridge injection on exit, and records the exact build identity in `BUILD.json`.

**Status:** local build infrastructure is implemented but the first full local ARMHF package run has not yet been recorded as evidence on this checkpoint.

## Current GitHub-hosted Actions blocker

Hosted Actions remains broken before job execution.

At PR head `fc4879c609ca95978c3ed202a8c485c6993a1d7c`, minimal **Actions runner probe** run `32475742329`, job `96751577470`, completed `failure` with `steps = null`. All normal workflows on that head failed before useful execution.

This remains an account/repository/runner infrastructure problem class, not evidence of a Kanki compiler failure. Do not change product source merely because those zero-step jobs are red.

Hosted CI can be repaired later and rerun as independent confirmation; it is no longer required to discover real compiler errors because the package can be built locally using the same canonical script.

## Desktop Anki parity state

The direct audit against pinned Anki 26.08.1 corrected and clarified several items:

- typed-answer `{{FrontSide}}` separator placement in the current bridge is structurally equivalent to desktop; `tests/bridge_source_contract.py` guards it, but executable fixtures remain pending;
- autoplay must be derived from effective deck config (`!disable_autoplay`) rather than AV-tag presence;
- answer-side question replay must honor effective `!skip_question_when_replaying_answer`, including filtered-card original deck behavior;
- the pinned v3 scheduler uses four rating buttons, so the Kindle four-button bar is not a parity defect for this pin;
- external reviewer navigation is explicitly prevented from replacing the persistent reviewer document;
- Lab126 CSS-pixel lifecycle behavior still requires PW6 proof.

See `docs/ANKI_DESKTOP_PARITY.md` for the exact source-level rationale.

## Renderer diagnostics state

Normal launch is designed to create:

```text
/mnt/us/extensions/kanki/render-debug/
/mnt/us/extensions/kanki/render-debug.previous/
```

Default metrics include bounded structural/layout information but no element text. Raw HTML/CSS/AV capture requires:

```text
/mnt/us/extensions/kanki/enable-render-capture
```

Raw capture is bounded and never included automatically in the redacted report. Diagnostic startup failure is a launcher error rather than a silent loss of observability.

## Previously achieved development evidence

Earlier iterations established useful but non-closing evidence for:

- Rust review state-machine behavior;
- persistent reviewer/`#qa` contract;
- card body classes;
- question/answer/rating flow contracts;
- replay SVG isolation from unrelated SVG;
- individual ARMHF native/audio compilations;
- parts of typed Anki integration;
- generic CSS compatibility tests.

Because behavior-changing commits landed afterward, these do not close the current release candidate. Final gates require same-candidate evidence.

## What is still not verified/closed

- first clean local canonical ARMHF package build on the current line;
- host fmt/clippy/unit/integration suite on the final candidate;
- disposable Anki collection queue/render/AV/type-answer/answer/bury/reopen corpus;
- deck-config autoplay/replay integration fixtures;
- normal/full/media sync lifecycle;
- ARMHF typed Anki library and ABI audit on the candidate;
- native GTK/WebKit shell and CSS-pixel behavior on PW6;
- audio sequence behavior on PW6/AirPods;
- renderer diagnostics daemon behavior on ARMHF/PW6;
- full generic CSS/renderer corpus including original unmodified representative APKGs;
- reproducibility characteristics of repeated canonical builds;
- clean install / historical upgrade / rollback;
- diagnostic privacy review;
- PW6 review/sync/scroll/sleep-wake/USB lifecycle acceptance;
- independent maintainer reproduction from repository docs only.

## Immediate next actions

1. Run `bash tools/local_package_docker.sh` on a developer Mac/Linux host and capture the first real compiler/package result.
2. If it fails, fix the first actual build error rather than inferring failure from GitHub's zero-step jobs.
3. If it succeeds, retain the ZIP, SHA-256, toolchain, ABI and GLIBC evidence and update issue #11.
4. Run/complete host and typed-Anki integration gates on the same commit.
5. Freeze one candidate only after non-hardware gates are green.
6. Install that exact ZIP on PW6 and run hardware acceptance, renderer metrics and audio/sync tests.
7. Repair/rerun hosted Actions later as independent confirmation, not as a separate build definition.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until the exact candidate artifact has passed the applicable software gates and PW6 hardware acceptance. The candidate may come from hosted CI or the documented local canonical builder; ad-hoc manually assembled ZIPs do not qualify.
