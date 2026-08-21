# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-21 UTC

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Current GitHub progress lineage includes VM evidence commit `a5d2a32a4fabaeaefe1674af892e056c6c4c6f35` and progress update `2e60d981f541119bdcd26ade7104f86691d9f7c0`.
- Current VM source checkpoint: `f4fafcd95749cb1318ec57fe4f351856fef8fd31` (not yet materialized as the canonical GitHub source commit).
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1).
- Detailed phase status: `kindle-anki-port/PROGRESS.md`.
- Detailed VM evidence: `kindle-anki-port/docs/VM_BUILD_20260821.md`.

This file is the authoritative continuation point. Update it after every material build, test, packaging, source-persistence, QEMU, or release change.

## User-required deliverables

1. Full maintainable ordinary source tree committed to GitHub, not only archive chunks.
2. Reproducible build scripts usable in the VM and later in GitHub Actions when quota is available.
3. PW6 ARM hard-float installation archive.
4. SHA-256 checksum, package contents, build provenance, ABI/GLIBC evidence, and test report.
5. Final package persisted on GitHub, not only in a temporary filesystem.
6. No bundled collection, media DB/content, credentials, logs, PID files, or user configuration.
7. No dependency on prior Kindle Anki patch runtimes or preload/template patch sets.
8. PW6 hardware acceptance recorded separately and never inferred from VM results.

## Architecture decision

This is a platform port of desktop Anki, not a card-template patch project.

- The pinned official Anki Rust backend remains authoritative for collection, scheduling, rendering, typed-answer comparison, media, sync, and undo.
- A named semantic C ABI exposes only reviewer/sync operations to the Kindle native processes.
- A narrow child bridge under Anki's generated `services` module is the only deliberate visibility crossing into generated backend methods.
- A native GTK2/WebKitGTK1 process owns the Kindle window, persistent WebView, focus, paging, keyboard, lifecycle, and worker supervision.
- An ES5 reviewer shell owns DOM replacement, replay controls, typed-input presentation, and generic old-WebKit compatibility.
- Audio and sync are separate supervised native workers.

## Major milestone reached in the VM

The former 26-error Rust visibility blocker is resolved.

The VM checkpoint `f4fafcd95749cb1318ec57fe4f351856fef8fd31` contains:

- `core/src/port.rs` semantic ABI;
- `core/src/services_bridge.rs` injected under `crate::services::kap_bridge`;
- deterministic pinned injector;
- GTK/WebKit host including Kindle pixel-density/full-content-zoom handling;
- GStreamer/mixersink-oriented audio worker;
- native `kap-sync` worker using official collection/full/media sync APIs;
- static, lifecycle, source-boundary, package and real-collection integration tests;
- ARMHF, package and QEMU smoke gate scripts.

### Host semantic result

Full official Anki rslib test suite:

```text
539 passed; 0 failed; 0 ignored
```

The release backend exports the expected named `kap_*` ABI including reviewer, health and sync operations.

### Real APKG integration result

Five real APKG fixtures passed the C ABI open/deck/queue/render/reveal/rate/close lifecycle. Typed-answer behavior was observed on `Advanced Vocabulary Complete (20 Units).apkg`; AV packets were observed on `4000 Essential English Words.apkg`, `新东方 雅思 乱序版.apkg`, and `百词斩考研.apkg`.

### ARM hard-float result

The following ARM outputs were produced and passed EABI/VFP/static audits:

```text
kap-app
kap-audio
kap-sync
libanki-kindle.so
```

All are ARM EABI5 hard-float. Workers require GLIBC_2.4. The backend's maximum referenced GLIBC symbol version is 2.18, matching the available KindleHF sysroot ceiling. This is not yet a substitute for loading them against the exact PW6 rootfs.

### Audited VM package checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256: 5a73a0d36941c26790b5fa8ed1a5cd9098ad3f1ab3b0222813888199a21442f4
```

The archive passes internal manifest verification, ZIP integrity, required-file checks, privacy/state-file policy, and exclusion of historical patch runtime dependencies. `BUILD.json` identifies source checkpoint `f4fafcd95749cb1318ec57fe4f351856fef8fd31` and the pinned Anki commit.

**Do not call this a final release yet.** The binary is currently a VM checkpoint because the ordinary source tree and final asset are not yet both persisted canonically on GitHub, and QEMU/PW6 acceptance remain open.

## Source persistence state

The canonical GitHub branch still contains the earlier split source archive staging (`part-*`, `restore.sh`) rather than the full ordinary VM checkpoint source tree. This is now the highest-priority repository task.

A local source archive checkpoint was generated from `f4fafcd`:

```text
Kindle-Anki-Port-source-f4fafcd.zip
SHA-256: cd6a3be68525ff0d629d58e0daf352cc27fae84a296a60be60bcc2b459158bf0
```

After ordinary-tree materialization is verified against this checkpoint/source manifest, the obsolete archive staging files should be removed.

## QEMU / rootfs state

The VM source checkpoint now includes:

```text
testenv/qemu/smoke.c
testenv/scripts/run-qemu-smoke.sh
```

The smoke harness cross-compiles as ARMv7 hard-float. Actual execution is pending because the current VM does not yet have both:

- a checksum-verified full PW6 rootfs mounted; and
- a working `qemu-arm` binary (package-network installation timed out during this run).

This is still VM-owned work and does **not** justify moving ordinary compilation to the user's local host.

## Execution environment

GitHub Actions runtime quota is exhausted. Iterative compilation/tests run in the VM/container. The VM has prepared offline Rust 1.92/Cargo dependencies, protoc, the pinned complete Anki source and KindleHF cross-toolchain. GitHub remains the canonical source/progress/final-artifact store.

If a later task genuinely requires a local host or physical Kindle, write exact inputs, commands, output artifacts and acceptance criteria to `CODEX_COORDINATION.md` before requesting it. No local-host action is required at this checkpoint.

## Ordered next actions

1. Materialize `f4fafcd95749cb1318ec57fe4f351856fef8fd31` into ordinary `kindle-anki-port/` GitHub source files.
2. Verify materialized source against the VM snapshot, then remove obsolete `part-*`/restore staging.
3. Re-run static, full rslib, real-APKG, ARMHF and package gates from the canonical materialized tree.
4. Persist the audited `Kindle-Anki-Port-PW6-armhf.zip`, exact SHA-256, `package-contents.txt`, ARMHF reports and build provenance durably on GitHub.
5. Obtain/extract the checksum-verified PW6 rootfs and run the QEMU backend/audio/sync smoke gate.
6. Add deterministic sync decision/error fixtures and broader renderer fixtures.
7. Only then start the PW6 hardware matrix: e-ink rendering/ghosting, typed keyboard, framework leave/re-enter, Bluetooth audio rerouting, suspend/resume and 50 relaunch cycles.

## Release record

Not released.

Current **VM checkpoint only**:

- source checkpoint: `f4fafcd95749cb1318ec57fe4f351856fef8fd31`;
- Anki: `e5a6fbe27fdd4d57d5f712191b4a753032e57853`;
- package SHA-256: `5a73a0d36941c26790b5fa8ed1a5cd9098ad3f1ab3b0222813888199a21442f4`;
- full Anki rslib tests: `539/539` pass;
- real APKG core integration: 5/5 fixtures pass;
- ARMHF static/ABI gate: pass;
- package audit: pass;
- QEMU exact-rootfs gate: pending;
- PW6 hardware acceptance: pending;
- final GitHub binary persistence: pending.

## Integrity rule

Do not mark the project complete merely because a ZIP exists in the VM. Completion requires maintainable ordinary GitHub source, a reproducible green build from that source, QEMU/rootfs target-runtime evidence, package audit, final GitHub artifact persistence, and a separately recorded PW6 hardware acceptance result.
