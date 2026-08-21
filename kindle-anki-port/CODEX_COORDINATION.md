# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-21

## Purpose

This file is the asynchronous coordination surface between the primary porting work and any Codex/local-machine worker. Read `HANDOFF.md` first. Do not import code from RAnki, `rewrite-v1`, or historical card-template patches.

## Current constraint

GitHub Actions runtime is exhausted. The primary worker is therefore building in an isolated Linux VM and will commit source, build scripts, diagnostics, checksums, and final binaries back to the `kindle-anki-port` branch.

The VM does not have ordinary outbound DNS. Large public dependencies may need to be supplied through GitHub files/artifacts or by a Codex worker with network access.

## Canonical pins

- Official Anki: `ankitects/anki@e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Kindle toolchain target: `armv7-unknown-linux-gnueabihf`
- Kindle GCC triple: `arm-kindlehf-linux-gnueabihf`
- koxtoolchain release: `2025.05`
- User target: PW6/Bellatrix4 hard-float userspace

## Current local work

The VM has:

- the restored independent source tree;
- corrected native frontend and GStreamer audio worker;
- a corrected semantic Rust adapter draft;
- a previously cross-built official Anki 26.08 backend artifact exporting:
  `anki_backend_open`, `anki_backend_open_collection`, `anki_backend_command`,
  `anki_backend_db_command`, `anki_backend_close_collection`, and
  `anki_backend_free`;
- firmware/source oracle reports for PW6.

The current branch also contains a verified source overlay in
`kindle-anki-port-overlay/` and an authoritative `HANDOFF.md`.

## Requests a Codex worker may take

Only claim a task by appending a dated entry under **Worker log** before editing.

### Task A — networked reproducible build environment

Prepare one of the following and commit exact instructions/checksums:

1. a complete offline Cargo vendor/cache sufficient to build the pinned Anki `rslib` with Rust 1.92.0; or
2. a local Docker/VM build script that fetches the pinned Anki source, initializes `ftl/core-repo` and `ftl/qt-repo`, applies `tools/inject_into_anki.py`, runs the semantic adapter tests, and cross-builds ARMHF with koxtoolchain 2025.05.

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
- Bluetooth re-route through Kindle GStreamer `mixersink`;
- no credentials, collection, media DB, logs, or PID state in releases;
- no RAnki or preload runtime.

## Worker log

Append entries in this format:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex task is currently claimed.

## Completion rule

A worker must not mark the port complete. Completion is recorded only in
`HANDOFF.md` after source materialization, reproducible build, host tests,
ARMHF ABI audit, package audit, GitHub persistence, and real-device acceptance.
