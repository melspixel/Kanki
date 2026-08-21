# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Product boundary and source map | complete | Independent desktop-Anki port; official Anki 26.08.1 pinned |
| Architecture | implementation-ready | Official `rslib` + named semantic C ABI + Kindle native host + persistent ES5 reviewer |
| Ordinary GitHub source tree | **complete** | `kindle-anki-port/` is materialized; split archive staging retired; canonical-source audit PASS |
| Rust semantic adapter | **host green** | Backend-owned `services::kap_bridge` resolved the private generated-service boundary |
| Official Anki backend tests | **green checkpoint** | `539 passed; 0 failed` against the pinned upstream |
| Real APKG core integration | **green for 5 decks** | open/deck/queue/question/reveal/rate/close exercised; typed answer and AV observed |
| Kindle native host | host/static green; ARMHF green checkpoint | strict C99/Werror gates and ARM EABI5 hard-float build pass |
| Web reviewer | runtime-fixture green; target rendering pending | persistent `#qa`, scripts, typed input, replay controls, paging and generic CSS compatibility covered |
| Audio | implementation integrated; hardware pending | GStreamer/`mixersink` worker self-test passes; real Bluetooth/audible routing requires PW6 |
| Sync | deterministic worker fixture green; lifecycle hardened; live account pending | sync worker owns the collection operation lock; wrapper signals no longer orphan an unprotected sync process |
| Launcher / collection ownership | deterministic fixture green; lifecycle hardened | double launch and reviewer/sync exclusion covered; signal cleanup and ownership-aware lock release added |
| Host release build | **green checkpoint** | release `libanki.so` exports the named `kap_*` ABI |
| ARMHF cross-build | **green checkpoint** | `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` produced for ARMv7 hard-float |
| ABI/GLIBC audit | **green against KindleHF sysroot** | workers require GLIBC_2.4; backend max GLIBC_2.18; target PW6 oracle ceiling GLIBC_2.35 |
| Package audit | **green checkpoint; privacy gate hardened** | stale ZIP checkpoint exists; current auditor additionally rejects backups, collection media and transient PID/lock state |
| QEMU user mode | static ARM sanity green | QEMU 8.2.2 runs a static ARMHF sanity executable |
| Exact PW6 runtime provenance | pinned | firmware/rootfs/loader/libc/WebKit hashes committed |
| Rootfs preparation pipeline | **implemented and fixture-green** | firmware/rootfs hashes, KindleTool extraction, `debugfs rdump`, runtime verifier and cleanup are gated |
| Exact-rootfs QEMU smoke | pending external runtime bytes | preparation/verifier/smoke harnesses exist; exact firmware/rootfs bytes are not currently mounted |
| Reproducible workflow | updated | canonical workflow consumes ordinary source; Actions quota is not used for iterative development |
| Final GitHub binary persistence | incomplete | final canonical-head package/reports must be rebuilt and stored durably |
| PW6 hardware acceptance | not started | real e-ink, touch, framework, Bluetooth, suspend and repeated relaunch evidence required |

## Major blockers already resolved

1. The former 26-error Rust visibility failure is resolved by injecting `core/src/services_bridge.rs` beneath Anki's generated `services` module and exposing only the narrow `pub(crate)` operations required by the C ABI.
2. The independent port is now ordinary source in GitHub rather than split archive chunks. `docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md` confirms that maintained build/package inputs resolve from `kindle-anki-port/` plus explicitly pinned upstream/toolchain inputs.
3. Host Rust, strict native C, reviewer fixtures, sync/lifecycle fixtures and ARM hard-float checkpoint builds have passed.
4. Rootfs extraction is no longer an ad-hoc manual step: it is a checksum-pinned, test-gated pipeline.
5. A reproduced sync-wrapper termination race is closed: the live sync worker now owns the shared operation lock, so wrapper death cannot make an open collection appear free.
6. Package privacy checks now reject pre-sync/pre-upgrade `*.anki2` backups, `collection.media`, `.sync-request`, `.opened-build`, operation-lock state and transfer PID files in addition to the previous credential/log/PID checks.

## Verified evidence

### Official backend

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

### Real APKG integration

Five user-representative decks passed the C ABI reviewer lifecycle:

- `4000 Essential English Words.apkg` — AV observed;
- `Advanced Vocabulary Complete (20 Units).apkg` — typed answer observed;
- `COCA-English.apkg`;
- `新东方 雅思 乱序版.apkg` — AV observed;
- `百词斩考研.apkg` — AV observed.

### Reviewer, sync and lifecycle fixtures

Persisted checkpoints include:

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
test_sync_worker: ok
```

The sync fixture covers required-action decisions, endpoint/timeout/server-USN propagation, full-sync direction conflicts, open/sync/full/media failures, credential non-disclosure and `abort -> close -> core_free` ordering. Lifecycle fixtures cover concurrent launches, operation locking, sync exclusion and stale-lock recovery.

Additional lifecycle hardening on 2026-08-22 reproduced a real wrapper-death hazard and changed the lock owner from the sync wrapper shell to the actual sync worker. New regression coverage verifies TERM forwarding/status, worker cleanup, wrapper-SIGKILL fail-closed ownership, normal worker error propagation and launcher signal cleanup. A targeted final launcher harness produced:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=no
```

Code checkpoint after lifecycle fixes:

```text
d589345428f28777cf413f97ac0602d565dbfa90
```

Detailed report: `docs/VM_LIFECYCLE_HARDENING_20260822.md`.

### Package privacy regression

The canonical package auditor and policy now reject transient/user state including `*.anki2`, `collection.media/**`, `.kap-operation.lock/**`, `.kap-operation.lock.pid.*`, `.sync-request`, `.opened-build`, `*.pid` and `*.log`.

A targeted synthetic-package regression returned:

```text
audit_package: ok sha256=ab6bbf82437a2e2ee1030205800ea8c242759c8699d25fa1e450c9d560c74039
package-runtime-state regressions: ok
```

That SHA belongs only to the synthetic test package. The latest package-audit code checkpoint is:

```text
5dbb090826eeb477a511d451ecc475269a560848
```

Detailed report: `docs/VM_PACKAGE_HARDENING_20260822.md`.

### ARMHF / GLIBC checkpoint

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

### Audited VM package checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It passed the then-current internal manifest, required-file, privacy/state and ZIP-integrity checks. It is explicitly stale for release provenance because it predates the lifecycle/package hardening above. A new final package must be regenerated from the eventual release head.

### Rootfs preparation checkpoint

The following exact Git blobs were deterministically tested in the VM:

```text
testenv/scripts/prepare-pw6-rootfs.py  dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
tests/test_prepare_pw6_rootfs.py        bd503d5842720c054531b3ca60ec708cd27de0eb
```

Result:

```text
python3 tests/test_prepare_pw6_rootfs.py
test_prepare_pw6_rootfs: ok
```

The pipeline verifies the firmware SHA-256/MD5, extracts with KindleTool, requires one rootfs image, verifies its SHA-256, extracts with unprivileged `debugfs rdump`, invokes the exact-runtime verifier, records provenance and removes partial output on failure. It is included in `run-static-gates.sh`.

Detailed report: `docs/VM_ROOTFS_PIPELINE_20260822.md`.

## Current blockers

### 1. Final canonical-head provenance

The complete static/backend/APKG/ARMHF/package sequence must be rerun from a VM checkout matching the latest canonical branch head. Existing green results are valid checkpoints but are not yet the immutable final release provenance. In particular, the last package predates the 2026-08-22 lifecycle and privacy hardening.

### 2. Exact PW6 runtime bytes

The firmware/rootfs identity and extraction pipeline are pinned, but the VM does not currently contain the exact checksum-matching PW6 5.19.6 firmware/rootfs bytes. Oracle reports alone are not accepted as runtime input. Once supplied privately, the pipeline can prepare the rootfs and run backend/audio/sync QEMU smoke.

### 3. Hardware-only acceptance

No VM can validate physical e-ink artifacts, real touch/IME focus, Amazon framework leave/re-enter behavior, audible Bluetooth routing, suspend/resume or long repeated relaunch behavior.

## Ordered next actions

1. Continue deterministic reviewer, lifecycle, sync and package hardening that does not require the rootfs.
2. Materialize the then-current canonical GitHub head in the build VM and rerun static, full `rslib`, real-APKG, ARMHF and package gates.
3. Obtain the checksum-matching PW6 5.19.6 firmware as a private input and run:

   ```text
   prepare-pw6-rootfs.py -> verify-pw6-rootfs.py -> run-qemu-smoke.sh
   ```

4. Persist the final canonical-head installer, SHA-256, manifest, package listing, ABI/GLIBC report and complete test report durably on GitHub.
5. Open the hardware-in-the-loop task only after every non-hardware gate is green and persisted.

## Completion definition

Software release completion requires complete maintainable ordinary source in GitHub; a green reproducible host and ARMHF build from the current canonical source; exact-rootfs QEMU smoke; ABI/GLIBC and package-policy audits; and `Kindle-Anki-Port-PW6-armhf.zip` plus SHA-256, manifest, contents and test report persisted durably on GitHub.

PW6 hardware acceptance is a separate final gate and must be recorded from actual device evidence rather than inferred from VM, mocks or CI.
