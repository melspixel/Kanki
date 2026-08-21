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
- `.github/workflows/ci.yml` — thin executor for canonical host and typed-Anki gates
- `.github/workflows/package.yml` — thin executor/artifact uploader for `tools/build_kindle_package.sh`

The detailed ownership map is maintained only in `docs/HANDOFF.md`; do not
restore the former component-workflow list here.

Local entry points:

```sh
sh tools/run_host_gates.sh
sh tools/local_anki_bridge_docker.sh
bash tools/local_package_docker.sh
bash tools/local_pw6_rootfs_audit.sh
```

`docs/TESTING.md` defines the closure gates. PW6 acceptance still requires the real device.

## 5. Current hosted-CI blocker

Current runner/run identifiers belong in `docs/STATUS.md`, not in this resume
router. The invariant is stable: a red job with no executed steps is hosted
infrastructure evidence, not a Kanki compiler failure. Do not edit product
source or duplicate build logic to chase it; use the canonical local executors
and treat hosted CI as later independent confirmation.

## 6. Immediate next actions from this checkpoint

The local host, typed-Anki and ARMHF/package baseline has been established.
Do not preserve a second mutable checklist here: read `docs/STATUS.md` for the
exact tested SHA, first current failure and next command, then follow the
takeover sequence in `docs/CODEX_HANDOFF.md`. GitHub Actions remains independent
confirmation and is not permitted to redefine the package recipe.

Gate D now also has the canonical fixed-firmware executor
`bash tools/local_pw6_rootfs_audit.sh`; its procedure and evidence boundary live
in `docs/LOCAL_BUILD.md`. A green rootfs/QEMU result never replaces Gate E on
the physical PW6.

## 7. Local package contract

`docs/LOCAL_BUILD.md` exclusively owns prerequisites, output inventory,
troubleshooting and evidence fields. The canonical definition remains
`tools/build_kindle_package.sh`; macOS/Linux runs it through
`tools/local_package_docker.sh`. A manually assembled ZIP is never evidence.

## 8. Renderer diagnostics contract

`docs/HANDOFF.md` owns the diagnostic/privacy contract and `docs/INSTALL.md`
owns the device procedure. Default evidence stays metadata-only; raw card
source remains bounded explicit opt-in and is never added to the redacted
bundle automatically.

## 9. Current desktop-parity findings

`docs/ANKI_DESKTOP_PARITY.md` owns semantic findings and
`docs/STATUS.md` owns which ones currently pass or remain open. Visual
similarity alone is never completion; diagnose via the backend/packet/DOM/CSS/
WebKit/Lab126/font-media chain in `docs/CODEX_HANDOFF.md`.

## 10. Evidence rules

`docs/TESTING.md` owns gate requirements and `docs/HANDOFF.md` owns the durable
evidence record. Issue #11 closes only with same-candidate evidence; never
inherit an older green result across behavior-changing commits.

## 11. PW6 acceptance order

`docs/TESTING.md` Gate E owns the ordered acceptance checklist and
`docs/INSTALL.md` owns clean install/full-sync/rollback steps. Start only after
the exact candidate passes non-hardware gates; never touch `anki_data`, modify
an input deck, or treat rootfs/QEMU evidence as physical PW6 evidence.

## 12. Release/merge rule

`docs/HANDOFF.md` owns release operations and `docs/STATUS.md` owns current
readiness. PR #10 stays Draft and issue #11 stays open until the same exact
candidate artifact has all applicable software and physical PW6 evidence.

## 13. Things that must never be hidden in chat

Before ending any development session, commit/update:

- `docs/STATUS.md` — what is implemented, verified, failing and next;
- issue #11 — closure evidence/checklist state;
- `docs/LOCAL_BUILD.md` if local compilation changes;
- an ADR if architecture/invariants changed;
- `docs/HANDOFF.md` if build/release/diagnostic procedures changed;
- this file if the resume entry point, blocker or immediate next action changed.

A future maintainer should need the repository and GitHub history only.
