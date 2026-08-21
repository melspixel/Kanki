# Resume Kanki rewrite from zero context

This is the first file to read when taking over the `rewrite-v1` work. The goal is that a maintainer can resume the project without chat history, local scratch files, undocumented commands, or dependence on GitHub-hosted runners.

## 1. Authoritative state

- Repository: `melspixel/Kanki`
- Active implementation branch: `rewrite-v1`
- Integration PR: `#10` (`rewrite-v1` -> `main`), intentionally kept Draft
- Closure tracker: issue `#11`
- `main` remains the last accepted legacy line until the rewrite passes hardware acceptance
- Target device: Kindle Paperwhite 12th generation / PW6, ARMv7 hard-float
- Production Anki core: pinned Anki 26.08.1 gitlink under `third_party/anki`
- KindleHF build toolchain: checksum-pinned koxtoolchain `2026.08`
- Canonical package recipe: `tools/build_kindle_package.sh`
- Local macOS/Linux package executor: `tools/local_package_docker.sh`

Never infer completion from a compile, a screenshot, or an old green job. Issue #11 plus evidence attached to the release candidate is the closure record.

Read `docs/ANKI_DESKTOP_PARITY.md` before changing reviewer behavior. Read `docs/LOCAL_BUILD.md` before changing package/build execution.

## 2. Current architectural invariants

These are design constraints, not implementation suggestions:

1. RAnki is reference-only. The rewrite must not execute or patch the RAnki binary.
2. No `LD_PRELOAD` backend redirection.
3. No hard-coded 420px logical viewport, media-query rewriting, or global zoom cap.
4. Kindle DPI uses feature-detected Lab126/WebKit CSS-pixel/full-content-zoom behavior when available.
5. The reviewer owns one persistent WebView and one persistent `#qa` document. Card changes update content; they do not recreate the whole browser page.
6. Anki access goes through semantic typed bridge functions. No numeric protobuf service/method IDs are allowed in application code.
7. Card compatibility is deck-agnostic. Never add selectors or behavior for COCA, a specific note type, a specific dictionary template, or a specific user's deck.
8. Audio controls may be constrained; unrelated SVG/images must remain untouched.
9. Sync must not race a second collection owner. Reviewer and sync collection lifetimes are explicit.
10. `/mnt/us/anki_data` is user data. Install, upgrade, rollback, diagnostics and uninstall must never delete or replace it.
11. New rewrite installs under `/mnt/us/extensions/kanki`, separate from legacy `/mnt/us/extensions/ranki`.
12. Release artifacts are self-identifying and manifest-verified. Mixed component versions must be rejected, not tolerated.
13. Privacy-safe renderer metrics are always available; raw card HTML/CSS capture is bounded and explicit opt-in only.
14. Build/release inputs use pinned/checksummed toolchain/source identities rather than floating release URLs.
15. GitHub Actions is an executor, not the build definition. Hosted CI and local build must invoke the same canonical package script.

If a proposed fix violates any invariant above, stop and redesign it.

## 3. Source map

### Core/domain

- `crates/kanki-domain/` — deterministic review/deck state and shared types
- `crates/kanki-backend/` — application-facing backend abstractions
- `crates/kanki-renderer/` — reviewer packet/rendering policy
- `crates/kanki-platform/` — platform boundary
- `crates/kanki-app/` — host/self-test executable

### Anki integration

- `bridge/anki_bridge.rs` — semantic review/deck/render bridge compiled into pinned Anki
- `bridge/sync_bridge.rs` — semantic sync bridge
- `bridge/kanki_bridge.h`, `bridge/kanki_sync_bridge.h` — C ABI consumed by Kindle executables
- `bridge/smoke.c` — ABI/integration smoke harness

### Kindle native layer

- `device/kanki_device.c` — GTK2/WebKit application and lifecycle
- `device/kanki_sync_cli.c` — sync process
- `device/kanki_raise.c` — existing-instance reactivation helper
- `device/kanki_diag_server.c` — loopback renderer metrics/raw-capture service on `127.0.0.1:17393`
- `device/audio/kanki_audio_server.c` — loopback audio service

### Reviewer/device assets

- `assets/device/` — deck/sync/reviewer shell pages
- `assets/reviewer/reviewer.js` — persistent `#qa`, script execution, AV/review protocol
- `assets/reviewer/reviewer.css` — minimal reviewer-owned CSS only
- `assets/reviewer/css_compat.js` — deterministic CSS source compatibility transform
- `assets/reviewer/css_runtime.js` — old-WebKit runtime compatibility behavior
- `assets/reviewer/mathjax_runtime.js` — persistent-`#qa` MathJax lifecycle adapter
- `assets/reviewer/diagnostics.js` — bounded privacy-safe computed-layout metrics and opt-in raw source capture

### Packaging/operations

- `scripts/kanki-launch.sh` — launcher, manifest verification, diagnostics/audio lifetime and component startup
- `scripts/kanki-sync.sh` — sync lifecycle
- `scripts/kanki-report.sh` — redacted diagnostic bundle; does not include raw card captures
- `packaging/` — config example and Kindle-home shortcuts
- `tools/install_kindlehf_toolchain.sh` — pinned/checksummed KindleHF toolchain installer
- `tools/install_mathjax.sh` — pinned/checksummed source-owned formula runtime installer
- `tools/create_reproducible_zip.py` — deterministic archive helper used only by the canonical package recipe
- `tools/run_host_gates.sh` — one-command host verification path
- `tools/build_kindle_package.sh` — canonical ARMHF build/package/ABI recipe used by CI and local builds
- `tools/local-builder.Dockerfile` — Ubuntu 24.04 + Rust 1.92.0 local builder environment
- `tools/local_package_docker.sh` — one-command Docker/OrbStack/Colima local package executor
- `docs/LOCAL_BUILD.md` — local-build requirements/evidence contract

### References

- `third_party/anki` — production core pin
- `third_party/kindle-sdk` — Kindle system/toolchain reference pin
- `third_party/ranki-reference` — historical behavior reference only
- `third_party/audiobook-koplugin` — pinned native Kindle GStreamer reference/helper source

## 4. Test/build entry points

Hosted workflows remain useful evidence/executors:

- `.github/workflows/actions-probe.yml` — minimal hosted-runner/account execution probe
- `.github/workflows/ci.yml` — Rust workspace, policy, reviewer contract, host self-test, ARM scaffold
- `.github/workflows/anki-bridge.yml` — typed Anki host bridge/integration
- `.github/workflows/anki-bridge-arm.yml` — typed Anki ARMHF build/ABI
- `.github/workflows/device.yml` — native Kindle device/diagnostics shell
- `.github/workflows/audio.yml` — audio service/helper
- `.github/workflows/css-compat.yml` — legacy WebKit CSS compatibility corpus
- `.github/workflows/package.yml` — hosted executor for `tools/build_kindle_package.sh`

Local entry points:

```sh
sh tools/run_host_gates.sh
bash tools/local_package_docker.sh
```

`docs/TESTING.md` defines the closure gates. PW6 acceptance still requires the real device.

## 5. Current hosted-CI blocker

GitHub-hosted Actions remains broken before job execution.

At PR head `fc4879c609ca95978c3ed202a8c485c6993a1d7c`, minimal **Actions runner probe** run `32475742329`, job `96751577470`, completed `failure` with `steps = null`. All normal workflows on the same head failed in the same pre-step manner.

Therefore:

- do **not** treat these red runs as source/compiler failures;
- do **not** shotgun-edit workflows to chase a job that never started;
- repository/account Actions policy, minutes/billing/budget or hosted-runner availability remains the likely infrastructure class to inspect.

However, hosted Actions is no longer a hard blocker for compilation: the canonical package recipe now has a local Docker executor.

## 6. Immediate next actions from this checkpoint

The local host, typed-Anki and ARMHF/package baseline has been established.
Do not preserve a second mutable checklist here: read `docs/STATUS.md` for the
exact tested SHA, first current failure and next command, then follow the
takeover sequence in `docs/CODEX_HANDOFF.md`. GitHub Actions remains independent
confirmation and is not permitted to redefine the package recipe.

## 7. Local package contract

The canonical package script:

```sh
bash tools/build_kindle_package.sh
```

requires Linux x86-64-compatible execution, Rust 1.92.0 and the documented host dependencies. On macOS use the wrapper:

```sh
bash tools/local_package_docker.sh
```

The wrapper forces `linux/amd64` because the pinned KindleHF toolchain is Linux x86-64-hosted. Apple Silicon Docker/OrbStack/Colima can emulate this platform; the first Anki build may be slow.

Expected output:

```text
out/local-kindle/Kanki-rewrite-hw3.zip
out/local-kindle/Kanki-rewrite-hw3.zip.sha256
out/local-kindle/package-contents.txt
out/local-kindle/package-exports.txt
out/local-kindle/package-glibc.txt
out/local-kindle/sysroot-glibc.txt
out/local-kindle/toolchain-info.txt
out/local-kindle/mathjax-info.txt
out/local-kindle/archive-info.txt
```

The script refuses a dirty root checkout by default, validates source gitlinks, installs/reuses the checksum-pinned KindleHF toolchain, restores temporary Anki source injection on exit, performs manifest/export/GLIBC gates, and records the exact build identity inside the package.

A local canonical build is valid build evidence. A ZIP assembled by ad-hoc copy commands is not.

## 8. Renderer diagnostics contract

Normal launch creates `/mnt/us/extensions/kanki/render-debug/` and starts `kanki-diag`. Failure to create/start diagnostics is explicit and aborts launch rather than silently losing observability.

Default `metrics.log` is privacy-safe: render/card identifier, side, body class, viewport/scroll/`#qa` geometry, DPR, and a bounded set of element tag/class/computed font/display/geometry fields. It does not include element text.

Raw source capture requires the sentinel `/mnt/us/extensions/kanki/enable-render-capture`. Raw captures may contain note content and are never copied into the default redacted report.

## 9. Current desktop-parity findings

Do not treat visual similarity alone as completion. `docs/ANKI_DESKTOP_PARITY.md` is the source of truth.

Current important state:

- typed-answer `{{FrontSide}}` separator placement and basic/cloze/empty/unknown-field behavior have pinned-backend executable fixtures; PW6 input/scroll remains pending;
- autoplay must come from effective deck config (`!disable_autoplay`) and is represented in the rewrite design/packet path;
- answer-side replay must honor effective `!skip_question_when_replaying_answer`, including filtered-card original-deck behavior;
- the pinned Anki v3 scheduler uses four answer buttons, so the four-button Kindle bar is not a parity defect for this pin;
- Lab126 CSS-pixel policy still needs lifecycle/device verification;
- ordinary reviewer HTTP(S) links are explicitly prevented from replacing the persistent reviewer document and need device-policy acceptance.
- checksum-pinned MathJax SVG output is exercised across dynamic persistent
  `#qa` renders; real PW6 geometry/performance remains open.

## 10. Evidence rules

For every closed item in issue #11, attach/reference evidence from the same candidate commit:

- exact commit SHA;
- executor/test identifier (GitHub run, local canonical build, or PW6 test);
- relevant artifact/log;
- target architecture;
- for rendering: fixture name and measured contract result;
- for hardware: device firmware, operation performed and result;
- for sync: desktop integrity/reopen result;
- for privacy: diagnostic bundle inspection result.

Never close a gate using a green result from an older source commit after behavior-changing code has landed.

## 11. PW6 acceptance order

Do not begin final hardware acceptance until host + bridge + ARMHF + package gates are green on the exact candidate commit.

On PW6:

1. back up the collection;
2. clean-install into `extensions/kanki` without touching `extensions/ranki` or `anki_data`;
3. capture build identity and system fingerprint;
4. confirm `render-debug/metrics.log` exists after first review render;
5. verify deck tree and collapse persistence;
6. verify question -> answer -> Again/Hard/Good/Easy, bury, restart;
7. run renderer corpus including representative original APKG decks without modifying them;
8. verify type-answer and effective autoplay/replay semantics;
9. verify long-card scrolling;
10. verify AirPods audio and repeated replay;
11. verify normal sync, restart, then desktop Anki integrity;
12. verify full-sync decision paths separately;
13. verify back/exit, duplicate launch, sleep/wake and USB/MTP lifecycle;
14. generate diagnostic ZIP and inspect for credentials/private database content;
15. if layout diagnosis requires raw content, enable raw capture deliberately for a bounded session and review it separately;
16. verify rollback while leaving `anki_data` untouched.

Any failure reopens the relevant gate. Do not compensate by editing the deck.

## 12. Release/merge rule

PR #10 remains Draft and issue #11 remains open until all applicable gates have same-candidate evidence. Hosted GitHub CI is useful independent confirmation but is no longer the sole build authority.

A release candidate may be produced by the documented local canonical builder when hosted Actions is unavailable, provided:

1. the checkout is clean and exact commit recorded;
2. canonical package script gates pass;
3. artifact SHA-256/toolchain/ABI evidence is retained;
4. remaining non-hardware gates are green on the same commit;
5. PW6 acceptance is completed against that exact ZIP;
6. `STATUS.md`, `HANDOFF.md`, issue #11 and release notes are updated before merge/tag.

## 13. Things that must never be hidden in chat

Before ending any development session, commit/update:

- `docs/STATUS.md` — what is implemented, verified, failing and next;
- issue #11 — closure evidence/checklist state;
- `docs/LOCAL_BUILD.md` if local compilation changes;
- an ADR if architecture/invariants changed;
- `docs/HANDOFF.md` if build/release/diagnostic procedures changed;
- this file if the resume entry point, blocker or immediate next action changed.

A future maintainer should need the repository and GitHub history only.
