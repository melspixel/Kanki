# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Product boundary and source map | complete | Independent desktop-Anki port; official Anki 26.08.1 pinned |
| Architecture | implementation-ready | Official `rslib` + named semantic C ABI + Kindle native host + persistent ES5 reviewer |
| Ordinary GitHub source tree | **complete** | `kindle-anki-port/` is materialized; split archive staging retired; canonical-source audit PASS |
| Rust semantic adapter | **host green** | Backend-owned `services::kap_bridge` resolved the private generated-service boundary |
| Official Anki backend tests | **green checkpoint** | `539 passed; 0 failed` against the pinned upstream; final clean-head rerun still required |
| Real APKG core integration | **green for 5 decks** | open/deck/queue/question/reveal/rate/close exercised; typed answer and AV observed |
| Kindle native host | host/static green; ARMHF green checkpoint | strict C99/Werror gates and ARM EABI5 hard-float build pass |
| Web reviewer | runtime-fixture green; target rendering pending | persistent `#qa`, scripts, typed input, replay controls, paging and generic CSS compatibility covered |
| Audio | implementation integrated; hardware pending | GStreamer/`mixersink` worker self-test passes; real Bluetooth/audible routing requires PW6 |
| Sync | deterministic worker fixture green; lifecycle hardened; live account pending | real worker owns the collection lock; wrapper-death and zombie-owner stale-lock windows have deterministic regressions |
| Launcher / collection ownership | deterministic fixture green; lifecycle hardened | double launch, reviewer/sync exclusion, signal cleanup, owner-checked release and zombie-owner reclamation covered |
| Build provenance | **hardened; targeted green** | host and ARMHF gates now require clean canonical project HEAD + exact pinned Anki HEAD before injection/Cargo; 11 targeted cases pass |
| Host release build | **green checkpoint** | release `libanki.so` exports the named `kap_*` ABI; must be rerun after provenance hardening |
| ARMHF cross-build | **green checkpoint** | `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` produced for ARMv7 hard-float; must be rerun after provenance hardening |
| ABI/GLIBC audit | **green against KindleHF sysroot** | workers require GLIBC_2.4; backend max GLIBC_2.18; target PW6 oracle ceiling GLIBC_2.35 |
| Package audit | **green checkpoint; privacy/provenance gates hardened** | stale ZIP checkpoint exists; current auditor rejects user/transient state and stale ARMHF provenance |
| QEMU user mode | static ARM sanity green | QEMU 8.2.2 runs a static ARMHF sanity executable |
| Exact PW6 runtime provenance | pinned | firmware/rootfs/loader/libc/WebKit hashes committed |
| Rootfs preparation pipeline | **implemented and fixture-green** | canonical Python verifier plus shell acquisition helper validate pinned SHA-256/MD5 and official Amazon sources before extraction |
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
6. A second stale-lock defect is closed: an exited gated worker can remain a zombie while `kill -0` succeeds; launch/sync liveness now checks `/proc/<pid>/stat` and treats `Z` as dead/reclaimable.
7. The PW6 shell acquisition helper now reads the real manifest keys, validates both firmware SHA-256 and MD5, uses only the Amazon alias/pinned Amazon object for automatic download, is executable in Git, and is covered by static gates.
8. Package privacy checks now reject pre-sync/pre-upgrade `*.anki2` backups, `collection.media`, `.sync-request`, `.opened-build`, operation-lock state and transfer PID files in addition to the previous credential/log/PID checks.
9. Package provenance regressions now require current ARMHF `source_commit`, pinned `anki_commit` and `ARMHF gates: PASS` before a ZIP can be assembled.
10. Host-backend and ARMHF build entry points now prove the project is a clean Git checkout at the declared `BUILD_COMMIT` and the Anki base checkout `HEAD` exactly matches `upstream.lock.json` before injection/Cargo. This closes the remaining path where dirty or wrong-base source bytes could generate deceptively green/stamped checkpoint artifacts.

## Verified evidence

### Official backend

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

This remains a valid persisted checkpoint, but it predates the newest source-identity preflight and must be rerun from the final clean release head.

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

Additional lifecycle hardening on 2026-08-22 reproduced a real wrapper-death hazard and changed the lock owner from the sync wrapper shell to the actual sync worker. Regression coverage verifies TERM forwarding/status, worker cleanup, wrapper-SIGKILL fail-closed ownership, normal worker error propagation and launcher signal cleanup. A targeted final launcher harness produced:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=no
```

A subsequent pre-publication SIGKILL regression exposed a zombie-owner edge case: the gated child had exited, but `kill -0` still reported success while it remained in state `Z`. `scripts/launch.sh` and `scripts/sync.sh` now use a zombie-aware liveness predicate and reclaim such stale owners. Targeted results:

```text
sh -n scripts/launch.sh                         PASS
sh -n scripts/sync.sh                           PASS
test_zombie_operation_lock.sh                   5/5 PASS
test_sync_wrapper_signal.sh                     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256             2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Canonical lifecycle blobs:

```text
scripts/launch.sh                    34ee8d5f106e31eb5e78509e1e6054c993bf9711
scripts/sync.sh                      7381fca8bdef86c57c580a367f5647173f76c892
tests/test_zombie_operation_lock.sh 54e3a7c899a69c2fb558b711439b6cb98083284f
```

Detailed reports: `docs/VM_LIFECYCLE_HARDENING_20260822.md` and `docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md`.

### Build provenance regressions

The audited entry points now enforce immutable source identities before building:

```text
PROJECT HEAD == declared BUILD_COMMIT
PROJECT subtree clean, including untracked source
ANKI HEAD == upstream.lock.json commit
ARMHF ANKI_COMMIT override, if present, == upstream.lock.json commit
```

Targeted exact-source results:

```text
test_armhf_provenance.py        6/6 PASS
ARMHF targeted log SHA-256      2ee0b646827cbeb83d05ea7572ad526d914826f4d480b5b485b2633edb17d538
test_host_backend_provenance.py 5/5 PASS
host targeted log SHA-256       897fd9ac46cc311276d31218d58a50cec190cad6582ebc518be803ccf2365db4
```

Current gate blobs at the targeted checkpoint:

```text
testenv/scripts/run-armhf-gates.sh        a81e8017034ba707aa0fca93248f44ec6c87dc1b
testenv/scripts/run-host-backend-gates.sh e58c1271f87815221faa5eb165c3fa96acb97df5
```

Both regressions are wired into `run-static-gates.sh`. Full official Anki and KindleHF compilation was not claimed in this continuation because the direct VM could not resolve `github.com`; see `docs/VM_BUILD_PROVENANCE_HARDENING_20260822.md`.

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

This is historical checkpoint evidence and must be regenerated after the build-provenance preflight from the final clean head.

### Audited VM package checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It passed the then-current internal manifest, required-file, privacy/state and ZIP-integrity checks. It is explicitly stale for release provenance because it predates the lifecycle/rootfs-helper/package/build-provenance hardening. A new final package must be regenerated from the eventual release head.

### Rootfs preparation checkpoint

The canonical Python pipeline remains:

```text
testenv/scripts/prepare-pw6-rootfs.py  dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
tests/test_prepare_pw6_rootfs.py        bd503d5842720c054531b3ca60ec708cd27de0eb
```

Persisted result:

```text
python3 tests/test_prepare_pw6_rootfs.py
test_prepare_pw6_rootfs: ok
```

The shell helper was audited and corrected after its first version referenced a non-existent `firmware.package_sha256` manifest key, omitted MD5 verification, depended on a non-executable mode in its test, and allowed an automatic community-mirror fallback. Current identities:

```text
testenv/scripts/prepare-pw6-rootfs.sh  d01b1d02ced887592926deb5de586b6f40a0a3f0  mode 100755
tests/test_rootfs_prepare_script.py    d7399aa70688b6128c61a916ff9dd8e758de94f3
```

Targeted helper validation:

```text
sh -n testenv/scripts/prepare-pw6-rootfs.sh       PASS
python3 tests/test_rootfs_prepare_script.py       Ran 3 tests; OK
```

The helper accepts automatic downloads only from the Amazon alias and pinned Amazon S3 object, validates firmware SHA-256 `72445ffe...143c` and MD5 `697aeb33c02f46b9b0911ab05c28b06d` before extraction, then delegates runtime verification to the canonical rootfs verifier. No firmware/rootfs bytes were acquired in this checkpoint.

Detailed reports: `docs/VM_ROOTFS_PIPELINE_20260822.md` and `docs/VM_ROOTFS_HELPER_HARDENING_20260822.md`.

## Current blockers

### 1. Final canonical-head provenance

The complete static/backend/APKG/ARMHF/package sequence must be rerun from a clean VM checkout matching the latest canonical branch head. Existing green results are valid checkpoints but are not the immutable final release provenance. The newest host/ARMHF gates will now fail closed if the project tree is dirty or the Anki base checkout is not exactly the pinned commit.

### 2. Exact PW6 runtime bytes

The firmware/rootfs identity and extraction pipeline are pinned, but the VM does not currently contain the exact checksum-matching PW6 5.19.6 firmware/rootfs bytes. Oracle reports alone are not accepted as runtime input. Once supplied privately, the pipeline can prepare the rootfs and run backend/audio/sync QEMU smoke.

### 3. Hardware-only acceptance

No VM can validate physical e-ink artifacts, real touch/IME focus, Amazon framework leave/re-enter behavior, audible Bluetooth routing, suspend/resume or long repeated relaunch behavior.

## Ordered next actions

1. Materialize the then-current canonical GitHub head in a network-capable build VM and run the complete static gate, including zombie-lock, rootfs-helper, package-provenance, ARMHF-provenance and host-backend-provenance regressions.
2. From that same clean commit and exact Anki 26.08.1 checkout, rerun full official `rslib`, five-real-APKG integration, ARMHF cross-build, ABI/GLIBC audit and package audit.
3. Obtain the checksum-matching PW6 5.19.6 firmware as a private input and run:

   ```text
   prepare-pw6-rootfs.py -> verify-pw6-rootfs.py -> run-qemu-smoke.sh
   ```

4. Persist the final canonical-head installer, SHA-256, manifest, package listing, ABI/GLIBC report, build provenance and complete test report durably on GitHub.
5. Open the hardware-in-the-loop task only after every non-hardware gate is green and persisted.

## Completion definition

Software release completion requires complete maintainable ordinary source in GitHub; a green reproducible host and ARMHF build from the current clean canonical source; exact-rootfs QEMU smoke; ABI/GLIBC and package-policy audits; and `Kindle-Anki-Port-PW6-armhf.zip` plus SHA-256, manifest, contents and test report persisted durably on GitHub.

PW6 hardware acceptance is a separate final gate and must be recorded from actual device evidence rather than inferred from VM, mocks or CI.
