# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-21 UTC

## Purpose

This file is the asynchronous coordination surface between VM-side porting work and any Codex/local-machine worker. Read `HANDOFF.md`, `PROGRESS.md`, `docs/VM_BUILD_20260821.md`, and `docs/TEST_ENVIRONMENT.md` first. Do not import code from historical Kindle Anki patch runtimes or card-template patch sets.

## Current constraints and status

GitHub Actions runtime is exhausted. Iterative builds run in an isolated Linux VM/container and all meaningful source, scripts, diagnostics, checksums, reports and final binaries must be persisted back to `melspixel/Kanki:kindle-anki-port`.

The VM now has a green host semantic checkpoint, full upstream rslib tests, five real-APKG C-ABI integration passes, ARMHF binaries and an audited package checkpoint. The remaining non-hardware work is primarily canonical source persistence, exact-PW6-rootfs/QEMU execution, additional sync/renderer fixtures and final artifact persistence.

## Canonical pins

- Official Anki: `ankitects/anki@e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- VM source checkpoint awaiting GitHub ordinary-tree materialization: `f4fafcd95749cb1318ec57fe4f351856fef8fd31`
- Kindle toolchain target: `armv7-unknown-linux-gnueabihf`
- Kindle GCC triple: `arm-kindlehf-linux-gnueabihf`
- koxtoolchain release: `2025.05`
- User target: PW6/Bellatrix4 hard-float userspace

## Responsibility boundary

### VM-owned work

The VM remains responsible for:

- canonical source materialization and source-manifest verification;
- official Anki semantic Rust/C ABI work;
- host unit/integration tests;
- ARMHF cross-compilation;
- ELF/ABI/GLIBC audits;
- QEMU/sysroot smoke tests when the verified rootfs is available;
- mocked Kindle service tests;
- package construction/privacy audit;
- GitHub source/report/final-artifact persistence.

The local host is **not required for ordinary compilation**.

### Local-host / physical-Kindle work

The local host is needed only as a bridge when the VM cannot reach the actual Kindle over USB/USBNetwork/SSH. It is required for evidence that depends on physical hardware:

- installing a checksum-verified package on the actual Kindle;
- collecting real framework, WebKit, framebuffer, input, audio and lifecycle logs;
- real e-ink refresh/ghosting/latency observation;
- actual touch controller and on-screen keyboard behavior;
- leaving fullscreen, changing Bluetooth settings and reopening the app;
- real Bluetooth pairing and audible route switching through `mixersink`;
- suspend/resume, power button, Wi-Fi/USB mode, memory pressure and repeated relaunch tests.

These are hardware-in-the-loop tests, not compilation prerequisites.

## Current evidence

VM checkpoint evidence is recorded in `docs/VM_BUILD_20260821.md`:

- full official Anki rslib: `539 passed; 0 failed`;
- five real APKG C-ABI integration fixtures pass;
- `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` are ARM EABI5 hard-float;
- backend max referenced GLIBC version: 2.18;
- audited VM package SHA-256: `5a73a0d36941c26790b5fa8ed1a5cd9098ad3f1ab3b0222813888199a21442f4`;
- QEMU smoke harness exists and cross-compiles; exact rootfs execution pending.

## Requests a Codex worker may take

Only claim a task by appending a dated entry under **Worker log** before editing.

### Task A — canonical source verification

If a Codex worker is available with GitHub write access, independently compare the materialized `kindle-anki-port/` tree with source checkpoint `f4fafcd95749cb1318ec57fe4f351856fef8fd31` / source snapshot SHA-256 `cd6a3be68525ff0d629d58e0daf352cc27fae84a296a60be60bcc2b459158bf0`. Report missing, extra or mismatched files. Do not change the upstream Anki pin.

### Task B — exact PW6 rootfs/QEMU input

Only if the VM cannot obtain the already identified firmware/rootfs itself, prepare a checksum-verified PW6 rootfs as a private build input. Output only:

- firmware package SHA-256;
- extracted rootfs-image SHA-256;
- extraction command/tool versions;
- rootfs directory/file manifest hash;
- a private path/reference usable by the VM.

Do not commit proprietary firmware/rootfs bytes to the source repository.

### Task C — package and lifecycle audit

Independently review `native/app.c`, `native/audio.c`, `native/sync.c`, `scripts/launch.sh`, `scripts/sync.sh`, and packaging for repeated launch/raise/exit, stale PID validation, clean shutdown, Bluetooth reroute, credentials/state exclusion and no historical runtime dependency.

### Task D — hardware-in-the-loop bridge

Do not begin until `HANDOFF.md` records a GitHub-persisted installation-package SHA-256 and test-bundle SHA-256.

Then verify checksums, back up `/mnt/us/anki_data`, install the package/test agent, run automated USBNetwork/SSH tests, ask the user only for irreducibly physical actions, sanitize logs and write the HIL report.

## Hardware report format

```text
Kindle-Anki-Port-PW6-HIL-Report-<build-commit>.zip
  report.json
  acceptance-matrix.md
  application.log
  lifecycle.log
  audio-events.log
  renderer-metrics.json
  screenshots/
  checksums.sha256
```

Do not include AnkiWeb keys, collection/media contents, device serials, Wi-Fi data or unsanitized logs.

## Worker log

Use:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex task is currently claimed.

## Current assignment

**No local-host action is requested.** Canonical source persistence, QEMU/rootfs work and final non-hardware gates remain VM-owned.

## Completion rule

A worker must not mark the port complete. Completion is recorded only in `HANDOFF.md` after ordinary source materialization, reproducible build, full tests, ARMHF ABI audit, exact-rootfs/QEMU smoke, package audit, GitHub artifact persistence and real-device acceptance. Hardware acceptance must never be inferred from VM or CI results.
