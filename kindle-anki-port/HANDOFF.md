# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1)
- Phase status: `PROGRESS.md`
- Architecture and source map: `docs/ARCHITECTURE.md`, `docs/SOURCE_MAP.md`
- Test design: `docs/TEST_ENVIRONMENT.md`
- VM evidence: `docs/VM_BUILD_20260821.md`, `docs/VM_CONTINUATION_20260821.md`, `docs/VM_CONTINUATION_20260822.md`
- Rootfs pipeline: `docs/VM_ROOTFS_PIPELINE_20260822.md`
- Canonical-source audit: `docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md`
- Lifecycle hardening: `docs/VM_LIFECYCLE_HARDENING_20260822.md`
- Package/privacy hardening: `docs/VM_PACKAGE_HARDENING_20260822.md`
- Local/Codex channel: `CODEX_COORDINATION.md`

This file is the authoritative continuation point. Update it after every material source, test, build, QEMU, package or release change.

## Non-negotiable project boundary

This is an independent platform port of desktop Anki, not a Ranki patch set.

- Official Anki `rslib` owns collection, scheduling, rendering, typed-answer comparison, media, sync and undo.
- The Kindle frontend communicates through a named semantic C ABI.
- Production does not contain Ranki, `rewrite-v1`, `LD_PRELOAD`, deck-name checks or note-type-specific CSS patches.
- GTK2/WebKitGTK1, e-ink, focus, touch, keyboard, audio and process lifecycle are Kindle platform responsibilities only.
- Hardware acceptance must never be inferred from VM, QEMU or mocked services.

## Required final deliverables

1. Complete maintainable ordinary source in GitHub.
2. Reproducible host and ARMHF build scripts.
3. Green host semantic/integration tests.
4. Green ARM hard-float, ABI, GLIBC and target-runtime gates.
5. `Kindle-Anki-Port-PW6-armhf.zip`.
6. External SHA-256, internal manifest, package contents, build provenance and test report.
7. Durable GitHub persistence of the final package and reports.
8. No collection, media, credentials, logs, PID/lock state or user configuration in the package.
9. Separate PW6 hardware-in-the-loop acceptance report.

## Current verified status

### Source and architecture

The independent port is ordinary source under `kindle-anki-port/`; obsolete archive staging has been retired. `docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md` records a PASS for build/package source-input independence: maintained project code resolves from `kindle-anki-port/` plus explicitly pinned Anki/Rust/KindleHF inputs.

The implementation contains:

- `core/src/port.rs` — semantic C ABI and reviewer state;
- `core/src/services_bridge.rs` — narrow backend-owned bridge into official generated services;
- `native/app.c` — Kindle native host;
- `native/audio.c` — GStreamer/`mixersink` audio worker;
- `native/sync.c` — collection/full/media sync worker;
- `web/` — persistent ES5 reviewer and compatibility layer;
- `scripts/` — launch and sync supervision;
- `tests/` and `testenv/` — deterministic fixtures, ARM/QEMU/package gates.

### Official Anki backend

The previous 26-error Rust visibility blocker is resolved by injecting `services_bridge.rs` beneath Anki's generated `services` module.

Persisted upstream test checkpoint:

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

Five real APKG fixtures passed collection/deck/queue/question/reveal/rate/close through the C ABI. Typed-answer behavior was observed on the Advanced Vocabulary fixture; AV packets were observed on three fixtures.

### Reviewer, sync and lifecycle

Persisted deterministic checkpoints include:

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
test_sync_worker: ok
```

Coverage includes:

- persistent `#qa`, body/card classes and script reinsertion;
- typed input, AV/replay/TTS routing and generic CSS compatibility;
- long-page paging and nested-scroll flattening;
- required sync decisions and full-sync direction conflicts;
- endpoint/timeout/server-USN propagation;
- open/sync/full/media errors and credential non-disclosure;
- `abort -> close -> core_free` shutdown order;
- concurrent launch, shared operation lock, sync exclusion and stale-lock recovery.

#### 2026-08-22 lifecycle hardening

A real sync-wrapper termination defect was reproduced: killing the wrapper could leave the real sync worker alive while the operation lock still named the dead wrapper. A later launcher could then reclaim that lock and open the collection concurrently.

The fix now:

- transfers `.kap-operation.lock` ownership from the shell wrapper to the real `kap-sync` worker PID;
- forwards TERM/INT/HUP and propagates normal worker status;
- returns conventional signal statuses (`143`, `130`, `129`);
- preserves worker-owned lock state across wrapper SIGKILL;
- uses ownership-checked, interruption-safe lock release in both sync and launch wrappers;
- adds `tests/test_sync_wrapper_signal.sh` and launcher signal regression coverage;
- gates the new test in `run-static-gates.sh`.

A second interruption window in the first ownership-aware launcher release implementation was caught by the targeted harness (`lock=yes` after TERM) and corrected. The final targeted launcher result was:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=no
```

Lifecycle code checkpoint:

```text
d589345428f28777cf413f97ac0602d565dbfa90
```

See `docs/VM_LIFECYCLE_HARDENING_20260822.md`.

### ARM hard-float checkpoint

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

The exact PW6 5.19.6 runtime oracle advertises through GLIBC_2.35. The build requirements are below that ceiling. A static ARMHF sanity executable runs under QEMU 8.2.2.

### Package/privacy hardening

The canonical package auditor and policy now fail closed on transient or user state, including:

```text
config.ini
*.log
*.pid
*.anki2
.sync-request
.opened-build
collection.media/**
.kap-operation.lock/**
.kap-operation.lock.pid.*
```

The expanded synthetic regression passed. The recorded synthetic ZIP hash is test evidence only, not a product hash:

```text
audit_package: ok sha256=ab6bbf82437a2e2ee1030205800ea8c242759c8699d25fa1e450c9d560c74039
package-runtime-state regressions: ok
```

Package-audit code checkpoint:

```text
5dbb090826eeb477a511d451ecc475269a560848
```

See `docs/VM_PACKAGE_HARDENING_20260822.md`.

### Audited package checkpoint — stale for release

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256: 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

This earlier checkpoint passed its then-current ZIP integrity, internal manifest, required-file and privacy/state gates. It is **not** the final release and is now explicitly stale because it predates the 2026-08-22 lifecycle/package hardening, the latest canonical branch head and exact-rootfs QEMU smoke.

## Exact PW6 runtime and rootfs pipeline

Manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned identities:

```text
firmware version:       5.19.6 / 4832160042
firmware SHA-256:       72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs-image SHA-256:   b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256:         a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256:           5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256:      6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC maximum:  2.35
```

Canonical implementation:

```text
testenv/scripts/prepare-pw6-rootfs.py
tests/test_prepare_pw6_rootfs.py
```

The preparation tool verifies firmware SHA-256/MD5, extracts with KindleTool, requires exactly one rootfs image, verifies its SHA-256, uses unprivileged `debugfs rdump`, invokes `verify-pw6-rootfs.py`, records provenance and removes partial output on failure.

Exact tested Git blobs:

```text
prepare-pw6-rootfs.py   dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
test fixture            bd503d5842720c054531b3ca60ec708cd27de0eb
```

VM result:

```text
python3 tests/test_prepare_pw6_rootfs.py
test_prepare_pw6_rootfs: ok
```

Relevant commits:

```text
477df23b2db90422660c34309eb8798f0b536e1f  rootfs preparation pipeline
d086bc2c4b22636a76de450735481316cb754b47  rootfs preparation fixture
3be9b9bf72f0a7e88066f0c774caa454b79eeb42  canonical static-gate integration
ef064fe91d618a8f1ac15f70fa68ab7881ffffcf  exact fixture-source alignment
52928234fe776f5b52fb4b0e0b5b95bdd3e2aff2  VM evidence report
```

The exact-rootfs QEMU gate is still pending the external checksum-matching firmware/rootfs bytes. Derived oracle reports are not accepted as substitutes.

Public metadata currently confirms PW6/Kindle Paperwhite 12th Generation firmware 5.19.6 build `4832160042`, but the VM still does not hold the actual checksum-matching firmware bytes. Do not treat metadata confirmation as runtime evidence.

## Current ordered next actions

1. Continue deterministic reviewer, sync, lifecycle and package hardening while no target rootfs is mounted.
2. Checkout/materialize the then-current canonical branch head in the build VM.
3. Run the full non-hardware sequence:

   ```text
   run-static-gates.sh
   full official rslib tests
   five-real-APKG integration
   run-armhf-gates.sh
   package-and-audit.sh
   ```

4. Obtain the checksum-matching PW6 5.19.6 firmware as a private input and run:

   ```text
   prepare-pw6-rootfs.py
   verify-pw6-rootfs.py
   run-qemu-smoke.sh
   ```

5. Regenerate the final installer from that exact canonical source commit.
6. Persist installer, SHA-256, manifest, package listing, ABI/GLIBC report and test report durably on GitHub.
7. Only then open the Codex/local-host hardware task for installation and real PW6 acceptance.

## Local-host boundary

The user's Mac is not required for ordinary compilation. It is only a bridge for the physical Kindle when USB/USBNetwork/SSH or irreducibly physical actions are required. `CODEX_COORDINATION.md` defines the hardware report format and privacy rules. No local-host task is currently requested.

## Release record

Not released.

Current release blockers:

- complete rerun from the latest canonical GitHub head;
- exact-rootfs dynamic QEMU smoke;
- durable final installer/report persistence;
- physical PW6 acceptance.

## Integrity rule

Do not mark the project complete merely because a ZIP exists in a VM. Completion requires a reproducible green build from the current canonical source, exact-rootfs QEMU evidence, package/ABI audits, durable GitHub release persistence and a separately recorded real-PW6 acceptance result.
