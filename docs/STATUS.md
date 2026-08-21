# Rewrite status

**Branch:** `rewrite-v1`  
**Integration:** PR #10, Draft  
**Closure tracker:** issue #11  
**Release state:** implementation in progress; not yet PW6-accepted  
**Target:** PW6 / ARMv7 hard-float  
**Checkpoint:** 2026-08-21
**Last fully recorded non-hardware baseline:** `dc53cc89603428b5b41bc9b223dc07a6222c2f65`

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
- typed bridge deck-config autoplay and answer-side question-replay fields, with bounded ordered reviewer/native sequence consumption and host fixtures;
- delegated reviewer and native WebKit navigation guards that preserve the persistent reviewer and block external navigation without logging full URIs;
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

### Verified local baseline

The current clean local non-hardware baseline is recorded for exact SHA
`dc53cc89603428b5b41bc9b223dc07a6222c2f65`:

- host: macOS 26.4 x86-64 with Docker Desktop engine 29.4.0, using the
  `linux/amd64` builder platform;
- `sh tools/run_host_gates.sh` — **PASS** using project-local Rust 1.92.0,
  Node 24.19.0 and jsdom 24.1.3; fmt, clippy, policy, native/source
  syntax, 13 Rust unit tests, doc tests, renderer/CSS/diagnostics contracts,
  semantic ordered-audio and external-navigation contracts, and the app
  self-test passed;
- `sh tools/local_anki_bridge_docker.sh` — **PASS**; pinned Anki built as a
  native x86-64 typed library; a backend-created disposable six-card
  collection passed queue counts, question/answer rendering, semantic
  question/answer sound and TTS extraction, `{{FrontSide}}`, basic typed-answer
  input/comparison, Again/Hard/Good/Easy persistence, user bury, close/reopen
  and health checks. Its sixth card was moved into a filtered deck from a
  normal deck whose autoplay and answer-side question replay were disabled;
  both question and prepared-answer packets preserved the two `false` semantic
  values and SQLite confirmed distinct current/original deck IDs. Independent
  sync-core open/close also passed; library SHA-256 was
  `066193df0ca31fe6a52d5fd6c837433bc68d350a4a25c9273f9035467d74de0d`;
- `bash tools/local_package_docker.sh` — **PASS**; typed Anki and all six
  ARMHF native executables built, renderer/reproducibility policy passed,
  `MANIFEST.sha256` verified, forbidden archive paths were absent, semantic
  exports were present and required GLIBC versions were within the pinned
  sysroot;
- package SHA-256:
  `429a6f2ae66b528efb7a4448b2e6400316f5be908b32bd93e12aecf9226fcfa8`;
- build identity pins Anki
  `e5a6fbe27fdd4d57d5f712191b4a753032e57853`, Kindle SDK
  `b4a6c99d718a7cf74935f36105c62491b4336a61`, audiobook helper
  `62edf76feb1b7f4af2f01754957e8d57eb3e7d67` and KindleHF 2026.08 SHA-256
  `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`.

This evidence is non-hardware baseline evidence, not release acceptance. It
does not prove native audio output on PW6/AirPods, cloze/edge-case type
answers, normal/full/media sync semantics, reproducibility across two clean
builds or PW6 behavior.

### Baseline failure ledger

- Initial audited SHA: `6e8330a4384af20af2c4404a12f8521638265147`.
- Host preflight first stopped at missing `cargo` (exit 69); Docker initially
  stopped at a non-running daemon. Both were environment preconditions, not
  source failures, and were resolved without global installation.
- The first real package compiler failure was `E0463` while compiling
  `serde_repr`, caused by sharing Anki's Cargo target directory through a
  Docker Desktop source bind. Commit `9edcb719b40c3f669415418ffd2cd19a6b14f07e`
  moved only that target cache to a named volume.
- The next compiler category was 31 typed-bridge errors against pinned Anki
  26.08.1. Commit `8f5fa0b2c6316a2f708bdafadec2ca391e17cd38`
  restored the semantic C ABI and pinned service/proto contract while retaining
  effective deck playback fields.
- Subsequent host categories fixed a forbidden global image rule, fail-open
  package assertions and portable diagnostics loopback binding in separate
  commits. The clean baseline above is the first SHA after all of them.
- Commit `512cb803c01cc6a9b2c94c99cd0c7ad908378c3e` fixed the next behavioral
  category: autoplay is now controlled only by the typed backend boolean,
  answer playback conditionally queues question then answer AV tags, and the
  loopback service owns one bounded ordered job. Host and ARMHF package gates
  pass at that exact SHA without changing generic SVG/image behavior.
- Commit `95525f8d195e3587eec666498d6cd6722dae2258` fixed the next behavioral
  category: delegated reviewer links and native WebKit policy now block
  external navigation while preserving same-document navigation and the
  persistent reviewer. The canonical host gate now includes this contract.
- The first disposable review integration run then exposed a product error:
  full rendering expanded raw `{{FrontSide}}` before AV extraction, duplicating
  question AV into the answer and changing its replay side. Commit
  `868b07a15ec09be2790f97e339e4a7984c8a7afb` switched to pinned-Anki partial
  rendering, expands only the semantic `FrontSide` replacement, and preserves
  q/a marker identity. A later `-2` versus `-3` bury mismatch was corrected in
  the test oracle after confirming pinned Anki records user bury as `-3`; no
  product bury behavior was changed for that mismatch.
- Commit `dc53cc89603428b5b41bc9b223dc07a6222c2f65` added pinned-backend
  executable evidence for both playback booleans with default-enabled and
  disabled effective deck values, including filtered-card original-deck
  inheritance. The first diagnostic and clean runs passed without a product
  change; modifying the bridge would have been an unjustified behavioral
  change.
- There is no red canonical local software gate at this checkpoint. The first
  missing executable category in the requested closure sequence is
  normal/full/media sync. Extend the disposable host recipe with controlled
  sync fixtures, then rerun `sh tools/local_anki_bridge_docker.sh`.

## Current GitHub-hosted Actions blocker

Hosted Actions remains broken before job execution.

At PR head `fc4879c609ca95978c3ed202a8c485c6993a1d7c`, minimal **Actions runner probe** run `32475742329`, job `96751577470`, completed `failure` with `steps = null`. All normal workflows on that head failed before useful execution.

This remains an account/repository/runner infrastructure problem class, not evidence of a Kanki compiler failure. Do not change product source merely because those zero-step jobs are red.

Hosted CI can be repaired later and rerun as independent confirmation; it is no longer required to discover real compiler errors because the package can be built locally using the same canonical script.

## Desktop Anki parity state

The direct audit against pinned Anki 26.08.1 corrected and clarified several items:

- typed-answer `{{FrontSide}}` separator placement is structurally equivalent to desktop and now has an executable basic-field fixture; cloze and edge-case fixtures remain pending;
- autoplay must be derived from effective deck config (`!disable_autoplay`) rather than AV-tag presence;
- answer-side question replay must honor effective `!skip_question_when_replaying_answer`, including filtered-card original deck behavior;
- the pinned-backend disposable fixture now proves enabled and disabled packet values plus filtered-card original-deck inheritance; native PW6 playback remains open;
- the pinned v3 scheduler uses four rating buttons, so the Kindle four-button bar is not a parity defect for this pin;
- external navigation is blocked by both reviewer JavaScript and native WebKit policy while same-document navigation remains allowed; PW6 policy-callback evidence remains pending;
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

- end-to-end ordered AV autoplay and answer-side question replay on PW6/AirPods;
- cloze and unknown/empty-field typed-answer integration fixtures;
- normal/full/media sync lifecycle;
- repeated clean-build comparison and reproducibility evidence;
- runtime ABI/loader proof against an audited PW6 rootfs or device;
- native GTK/WebKit shell and CSS-pixel behavior on PW6;
- audio sequence behavior on PW6/AirPods;
- renderer diagnostics daemon behavior on ARMHF/PW6;
- full generic CSS/renderer corpus including original unmodified representative APKGs;
- clean install / historical upgrade / rollback;
- diagnostic privacy review;
- PW6 review/sync/scroll/sleep-wake/USB lifecycle acceptance;
- independent maintainer reproduction from repository docs only.

## Immediate next actions

1. Exercise normal/full/media sync semantics with disposable state, controlled endpoints and no credentials in logs, then rerun `sh tools/local_anki_bridge_docker.sh`.
2. Add cloze and unknown/empty-field typed-answer fixtures without adding note-type-specific product behavior.
3. Extend the renderer corpus with generic fixtures and original, unmodified representative APKGs.
4. Repeat the clean canonical package build on the eventual candidate and compare manifests/artifact characteristics.
5. Freeze one candidate only after non-hardware gates are green.
6. Install that exact ZIP on PW6 and run hardware acceptance, renderer metrics and audio/sync tests.
7. Repair/rerun hosted Actions later as independent confirmation, not as a separate build definition.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until the exact candidate artifact has passed the applicable software gates and PW6 hardware acceptance. The candidate may come from hosted CI or the documented local canonical builder; ad-hoc manually assembled ZIPs do not qualify.
