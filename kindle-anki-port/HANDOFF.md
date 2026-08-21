# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1)
- Detailed phase status: `kindle-anki-port/PROGRESS.md`
- Initial VM build evidence: `kindle-anki-port/docs/VM_BUILD_20260821.md`
- First continuation evidence: `kindle-anki-port/docs/VM_CONTINUATION_20260821.md`
- Latest continuation evidence: `kindle-anki-port/docs/VM_CONTINUATION_20260822.md`
- Target-runtime test design: `kindle-anki-port/docs/TEST_ENVIRONMENT.md`

This file is the authoritative continuation point. Update it after every material build, test, package, source-persistence, QEMU or release change.

## User-required deliverables

1. Full maintainable ordinary source tree committed to GitHub, not only archive chunks.
2. Reproducible build scripts usable in the VM and later in GitHub Actions when quota is available.
3. PW6 ARM hard-float installation archive.
4. SHA-256 checksum, package contents, build provenance, ABI/GLIBC evidence and test report.
5. Final package persisted durably on GitHub, not only in a temporary VM/chat filesystem.
6. No bundled collection, media DB/content, credentials, logs, PID files or user configuration.
7. No dependency on Ranki, `rewrite-v1`, `LD_PRELOAD` or historical card-template patch runtimes.
8. PW6 hardware acceptance recorded separately and never inferred from VM/QEMU results.

## Architecture decision

This is a platform port of desktop Anki, not a card-template patch project.

- Pinned official Anki Rust `rslib` remains authoritative for collection, scheduling, rendering, typed-answer comparison, media, sync and undo.
- A named semantic C ABI exposes only reviewer/sync operations to Kindle native processes.
- A narrow child bridge under Anki's generated `services` module is the deliberate visibility crossing into generated backend methods.
- A native GTK2/WebKitGTK1 process owns the Kindle window, persistent WebView, focus, paging, keyboard, lifecycle and worker supervision.
- An ES5 reviewer shell owns DOM replacement, replay controls, typed-input presentation and generic old-WebKit compatibility.
- Audio and sync are separate supervised native workers.

## Canonical source status — milestone complete

The independent port now exists as ordinary GitHub files under `kindle-anki-port/`.

Temporary root `part-00` … `part-08`, `restore.sh`, the old source-ZIP checksum, and `kindle-anki-port-overlay/overlay.part-*` staging were retired in:

```text
0cf4716d8f66af96d38233ec5f723151787278d7
repo: retire archive staging after ordinary source materialization
```

The retained root-level `src/`, `scripts/`, `tools/` and legacy documentation belong to the historical Kanki/Ranki project from the repository's main lineage. They are not production inputs to the independent port. The root README makes this distinction explicit, and the legacy workflow is excluded from `kindle-anki-port` pushes.

## Semantic / host status

The former 26-error Rust visibility blocker is resolved by `core/src/services_bridge.rs` injected under `crate::services::kap_bridge`.

Persisted full official Anki rslib evidence:

```text
539 passed; 0 failed; 0 ignored
```

Five real APKG fixtures passed the C ABI open/deck/queue/render/reveal/rate/close lifecycle. Typed-answer behavior was observed on `Advanced Vocabulary Complete (20 Units).apkg`; AV packets were observed on three real decks.

The previous complete static/lifecycle checkpoint passes injector idempotence, semantic/source contracts, JavaScript syntax/DOM contract, strict C99/Werror native builds, worker self-tests, launch lifecycle and deterministic sync-worker fixtures.

### 2026-08-22 sync hardening and reviewer runtime evidence

The current ordinary source additionally contains the following material source/test commits:

```text
36c73d49251ca73d8448434b247e722c46c4fa99  sync: reject conflicting full-sync modes
4a27352fa7718e2d8e48fc603582e7d55f2b0653  test: add deterministic sync error and shutdown tracing
78fbfa38c4599673eb356f88597bf7ea0707e9c1  test: expand sync decision error and abort fixtures
a3bdeaf924b5fb6d802c9454ac4c5435d3eb5b16  test: add reviewer runtime fixture matrix
3e139cb006be449b385ad26470ebe9327dc15393  test: include reviewer runtime fixtures in static gate
```

The sync worker now rejects simultaneous `--full-upload` and `--full-download` with status 64 rather than silently letting argument order choose a destructive direction. Its deterministic fixture now covers required-action decisions, endpoint/timeout/server-USN propagation, error cleanup, credential non-disclosure and SIGTERM shutdown ordering. Exact source blobs were Git-object-hash checked before local execution.

```text
test_sync_worker: ok
```

The dependency-free Node/vm reviewer harness drives the production `window.kapReviewer` API with ten runtime fixture groups covering mixed CJK/Latin rendering, body classes/CSS/intervals, typed input, inline-script replacement, replay controls/AV routing, nested-scroll flattening, answer behavior, state transitions, failure telemetry and touch paging.

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
```

These are genuine executable fixture advances, but they do **not** replace the required full canonical-head static/rslib/ARMHF/package rerun.

## Fresh ARM hard-float checkpoint

A fresh ARMHF rebuild was completed in the VM from source checkpoint `f1f5ff0a9edd37a14a5bd48213fcf1c21256a835` using Rust/Cargo 1.92.0 and KindleHF GCC 14.2.0.

```text
ARMHF gates: PASS
```

Produced:

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

The build gate derives the compatibility ceiling from the KindleHF target sysroot rather than a hard-coded host-like value. KindleHF's sysroot ceiling is GLIBC_2.18. The exact PW6 5.19.6 runtime `libc.so.6` oracle advertises through GLIBC_2.35, so the checkpoint backend requirement is below both ceilings.

This remains checkpoint evidence; the final package must be regenerated from a VM materialization matching the current canonical GitHub source head.

## Fresh audited package checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256: 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

This VM checkpoint passes:

- internal `MANIFEST.sha256` verification;
- ZIP integrity;
- required-file checks;
- path/privacy/state policy;
- exclusion of collections, media DB/content, credentials, logs/PIDs and historical patch runtimes.

It contains the ARM backend/app/audio/sync binaries, Web assets, launcher/sync scripts, manifest/build metadata and Kindle document shortcuts.

**Do not call this the final release.** Its build provenance still points to a VM checkpoint rather than the current canonical GitHub source head, and exact-rootfs QEMU plus final GitHub binary persistence remain open.

## Exact PW6 5.19.6 runtime pin

The exact target manifest is committed at:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned evidence:

```text
firmware:              Kindle 5.19.6 / version code 4832160042
firmware SHA-256:      72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs-image SHA-256:  b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256:        a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256:          5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256:     6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max:      2.35
```

`testenv/scripts/verify-pw6-rootfs.py` validates these hashes/version markers before QEMU is allowed to run.

The VM currently retains the prior exact-rootfs extraction/oracle reports and hashes, including the rootfs-image SHA above, but not the rootfs bytes themselves. Reports are not accepted as runtime input.

## QEMU state

QEMU user-mode is available in the VM:

```text
qemu-arm 8.2.2
```

A statically linked ARMv7 hard-float binary cross-built with KindleHF executes successfully:

```text
kap qemu armhf static sanity: ok
QEMU host sanity: PASS
```

The KindleHF compiler sysroot was tested as a possible dynamic stand-in and rejected: even a trivial dynamic ARM program trips an `ld.so` relocation assertion. That sysroot is therefore not accepted as PW6 runtime evidence.

Exact-rootfs QEMU execution remains pending because the current VM has verified hashes/oracle reports but not the complete extracted PW6 rootfs bytes. Current VM package-network/DNS access is restricted. This is an external test-input limitation, not a code/compiler blocker and not a reason to move ordinary compilation to the user's local host.

## Reproducibility definition

`.github/workflows/kindle-anki-port.yml` builds directly from ordinary `kindle-anki-port/` source files. It defines:

- static/native/lifecycle gates, including the new reviewer runtime fixture matrix;
- exact Anki + Fluent source fetch;
- Rust 1.92.0 host full-rslib gate;
- KindleHF ARM hard-float cross-build;
- target-sysroot ABI/GLIBC audit;
- QEMU static ARM host sanity;
- package assembly/audit;
- source archive, logs, reports and artifact retention.

GitHub Actions quota is exhausted, so this workflow is maintained as the independent reproducibility definition and will be rerun when quota is available. Iterative compilation remains VM-owned.

## Current ordered next actions

1. Materialize the **then-current canonical GitHub head** in a build-capable VM and rerun the complete static gate, full rslib, real-APKG, ARMHF and package gates so final provenance is tied to the canonical source commit rather than `f1f5ff0…`.
2. Obtain/extract the checksum-verified PW6 5.19.6 rootfs as a private VM test input; run `verify-pw6-rootfs.py` and the backend/audio/sync QEMU smoke gate.
3. Extend renderer evidence from the new public-API fake-DOM runtime matrix toward exact-rootfs/target-WebKit execution and additional backend-rendered packet fixtures where useful.
4. Build the final canonical-head `Kindle-Anki-Port-PW6-armhf.zip`; persist it, SHA-256, package contents, ABI/GLIBC reports and test report durably on GitHub.
5. Only then start physical PW6 hardware acceptance: e-ink rendering/ghosting, typed keyboard, framework leave/re-enter, Bluetooth audio rerouting, suspend/resume and repeated relaunch.

## Local-host / Codex boundary

No local host is required for ordinary compilation. If the exact rootfs cannot be transported into the VM directly, `CODEX_COORDINATION.md` contains a narrowly scoped private-input task. Physical Kindle work remains a later hardware-in-the-loop gate.

## Release record

Not released.

Current checkpoint evidence:

- canonical ordinary-source milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`;
- Anki: `e5a6fbe27fdd4d57d5f712191b4a753032e57853`;
- full Anki rslib tests: `539/539` pass (persisted checkpoint);
- real APKG core integration: 5/5 fixtures pass;
- sync decision/error/shutdown fixture: pass on exact current source blobs from the 2026-08-22 implementation commits;
- reviewer public-API runtime fixture matrix: 10 groups pass;
- fresh ARMHF static/ABI gate: pass checkpoint;
- fresh package audit: pass checkpoint;
- fresh VM package SHA-256: `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225` (checkpoint only);
- QEMU static ARM sanity: pass;
- exact PW6 rootfs manifest/verifier: present;
- exact-rootfs dynamic QEMU gate: pending rootfs bytes;
- full canonical-head host/rslib/ARMHF/package rerun: pending;
- final canonical-head GitHub binary persistence: pending;
- PW6 hardware acceptance: pending.

## Integrity rule

Do not mark the project complete merely because a ZIP exists in the VM. Completion requires a reproducible green build from the current canonical ordinary GitHub source, exact-rootfs QEMU evidence, package/ABI audits, durable final GitHub artifact persistence and a separately recorded real-PW6 acceptance result.
