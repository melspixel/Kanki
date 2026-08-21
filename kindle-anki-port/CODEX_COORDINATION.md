# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-21

## Purpose

This file is the asynchronous coordination surface between the VM-side porting work and any Codex/local-machine worker. Read `HANDOFF.md`, `PROGRESS.md`, and `docs/TEST_ENVIRONMENT.md` first. Do not import code from RAnki, `rewrite-v1`, or historical card-template patches.

## Current constraints

GitHub Actions runtime is exhausted. Iterative builds therefore run in an isolated Linux VM/container and all meaningful source, scripts, diagnostics, checksums, and final binaries must be committed or persisted back to `melspixel/Kanki:kindle-anki-port`.

The VM may not have unrestricted outbound DNS or privileged USB access. That does not make the user's host a required compiler; it only means large public dependencies, a target rootfs, or physical-device access may need to be supplied through GitHub files/artifacts or a Codex worker with network/USB access.

## Canonical pins

- Official Anki: `ankitects/anki@e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Kindle toolchain target: `armv7-unknown-linux-gnueabihf`
- Kindle GCC triple: `arm-kindlehf-linux-gnueabihf`
- koxtoolchain release: `2025.05`
- User target: PW6/Bellatrix4 hard-float userspace

## Responsibility boundary

### VM-owned work

The VM-side implementation remains responsible for:

- official Anki source integration and semantic Rust/C ABI repair;
- host unit/integration tests;
- ARMHF cross-compilation;
- ELF/ABI/GLIBC audits;
- QEMU/sysroot smoke tests when the rootfs is available;
- mocked Kindle service tests;
- package construction and privacy/policy audit;
- source, logs, reports, and release persistence to GitHub.

The local host is **not required for ordinary compilation**.

### Local-host / physical-Kindle work

The local host is needed only as a bridge when the VM cannot reach the Kindle over USB/USBNetwork/SSH. It is required for evidence that depends on the physical device:

- installing a checksum-verified package on the actual Kindle;
- collecting real framework, WebKit, framebuffer, input, audio, and lifecycle logs;
- real e-ink refresh/ghosting/latency observation;
- actual touch controller and on-screen keyboard behavior;
- leaving fullscreen, changing Bluetooth settings, and reopening the app;
- real Bluetooth pairing and audible route switching through `mixersink`;
- suspend/resume, power button, Wi-Fi/USB mode, memory pressure, and repeated relaunch tests.

These are hardware-in-the-loop tests, not compilation prerequisites.

## Current local work

The VM has or has previously had access to:

- the restored independent source tree;
- native frontend and GStreamer audio worker drafts;
- a semantic Rust adapter draft;
- firmware/source oracle reports for PW6;
- build diagnostics and source checkpoints.

The canonical branch contains `HANDOFF.md`, `PROGRESS.md`, and `docs/TEST_ENVIRONMENT.md`; source materialization and backend compilation remain in progress.

## Requests a Codex worker may take

Only claim a task by appending a dated entry under **Worker log** before editing.

### Task A — networked reproducible build environment

Prepare one of the following and commit exact instructions/checksums:

1. a complete offline Cargo vendor/cache sufficient to build the pinned Anki `rslib` with Rust 1.92.0; or
2. a local Docker/VM build script that fetches the pinned Anki source, initializes `ftl/core-repo` and `ftl/qt-repo`, applies `tools/inject_into_anki.py`, runs semantic adapter tests, and cross-builds ARMHF with koxtoolchain 2025.05.

Do not change the upstream pin.

### Task B — semantic adapter API review

Review `core/src/port.rs` against the pinned official Anki sources. Verify:

- collection open/close;
- deck tree/current deck/collapse state;
- queued-card retrieval;
- template rendering and AV extraction;
- typed-answer marker parsing, cloze extraction, and `compare_answer`;
- `describe_next_states` and `answer_card` state mapping;
- bury semantics;
- ownership/freeing across the C ABI.

Report exact compile errors or submit a narrowly scoped fix. Do not replace official scheduling/rendering behavior with local algorithms.

### Task C — package and lifecycle audit

Review `native/app.c`, `native/audio.c`, `scripts/launch.sh`, and packaging for:

- repeated launch/raise/exit behavior;
- stale PID verification before termination;
- clean collection and audio shutdown;
- Bluetooth reroute through Kindle GStreamer `mixersink`;
- no credentials, collection, media DB, logs, or PID state in releases;
- no RAnki or preload runtime.

### Task D — hardware-in-the-loop bridge

Do not begin until `HANDOFF.md` records an installation package SHA-256 and test-bundle SHA-256.

Then:

1. verify both checksums;
2. detect the mounted Kindle safely;
3. back up `/mnt/us/anki_data` without altering it;
4. install the package and hardware test agent;
5. use USBNetwork/SSH where available to run automated tests;
6. ask the user only for irreducibly physical actions;
7. collect and sanitize a report bundle;
8. update `HANDOFF.md` with exact results.

## Hardware report format

Create:

```text
Kindle-Anki-Port-PW6-HIL-Report-<build-commit>.zip
```

Containing:

```text
report.json
acceptance-matrix.md
application.log
lifecycle.log
audio-events.log
renderer-metrics.json
screenshots/
checksums.sha256
```

Do not include AnkiWeb keys, collection/media contents, device serials, Wi-Fi data, or unsanitized logs.

## Worker log

Append entries in this format:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex task is currently claimed.

## Current assignment

No local-host action is requested yet. VM-side host compilation, integration tests, ARMHF build, and package audit must become green first.

## Completion rule

A worker must not mark the port complete. Completion is recorded only in `HANDOFF.md` after source materialization, reproducible build, host tests, ARMHF ABI audit, package audit, GitHub persistence, and real-device acceptance. Hardware acceptance must never be inferred from VM or CI results.
