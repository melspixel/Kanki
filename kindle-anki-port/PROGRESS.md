# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Product boundary and source map | complete | Independent desktop-Anki reviewer port; official Anki 26.08.1 pinned |
| Architecture | complete enough to implement | Official rslib + semantic C ABI + Kindle native host + persistent ES5 reviewer |
| Ordinary GitHub source tree | **complete** | `kindle-anki-port/` materialized; temporary `part-*`/restore/overlay staging retired in `0cf4716d8f66af96d38233ec5f723151787278d7` |
| Rust semantic adapter | **host-green checkpoint** | Backend-owned `services::kap_bridge` resolves prior private-service E0624 blocker |
| Official Anki rslib tests | **green checkpoint** | `539 passed; 0 failed` against pinned Anki 26.08.1 |
| Real APKG core integration | **green for 5 decks** | question/reveal/rate/close exercised; typed answer observed; AV observed on 3 decks |
| Kindle native host | host/static green checkpoint, ARMHF green checkpoint | strict C99/Werror gates pass; fresh ARM EABI5 hard-float binary produced; canonical-head rerun pending |
| Web reviewer | **runtime-fixture green; device rendering pending** | static/ES5/CSS contracts plus 10-group public-API reviewer runtime matrix pass; real WebKit/e-ink remains device/rootfs work |
| Audio | implementation integrated, device audio pending | GStreamer/mixersink worker self-test passes; real Bluetooth/audible route requires PW6 |
| Sync | **deterministic decision/error fixture green; live-account pending** | collection/full/media/abort ABI plus shutdown/error matrix; conflicting full-sync directions now rejected |
| Launcher / collection ownership | **race reproduced and repaired; deterministic fixture green** | shared atomic launch/sync operation lock prevents double-launch and reviewer/sync concurrent collection opens; stale-lock recovery tested |
| Static/lifecycle tests | **green checkpoint plus current isolated fixture evidence** | prior complete gate green; current sync/reviewer/lifecycle regressions pass exact-source local tests; full canonical-head gate rerun pending |
| Host release build | **green checkpoint** | release `libanki.so` built and exports named `kap_*` ABI |
| ARMHF cross-build | **fresh green checkpoint** | `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` rebuilt as ARMv7 EABI5 hard-float |
| ABI/GLIBC audit | **green against KindleHF sysroot** | workers GLIBC_2.4; backend max GLIBC_2.18; exact PW6 5.19.6 runtime libc ceiling independently pinned as GLIBC_2.35 |
| Package audit | **fresh green VM checkpoint** | ZIP SHA-256 `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225`; not final-release provenance |
| QEMU user-mode availability | **green** | QEMU 8.2.2 executes a static ARMHF sanity binary successfully |
| Exact PW6 rootfs provenance | **pinned** | firmware/rootfs/loader/libc/WebKit hashes committed in `testenv/qemu/pw6-5.19.6-rootfs-manifest.json` |
| Exact-rootfs QEMU smoke | pending external input | verification harness exists; complete extracted PW6 rootfs bytes are not currently mounted in VM |
| Reproducible CI definition | **updated** | independent workflow builds directly from ordinary source; legacy Ranki workflow excluded from this branch |
| GitHub final binary persistence | incomplete | source/docs are canonical; final canonical-head package/report still must be built and persisted durably |
| PW6 acceptance | not started | physical e-ink/touch/framework/Bluetooth/suspend/relaunch evidence required |

## Major blockers already resolved

The former 26-error Rust visibility blocker is resolved. The semantic port no longer calls generated private service methods from crate root. `core/src/services_bridge.rs` is injected as a child of Anki's generated `services` module and exposes only the narrow `pub(crate)` operations required by the Kindle ABI.

The repository is also no longer dependent on split source archives for the independent port. Ordinary source materialization is complete, and the obsolete root/overlay archive staging was removed after verification.

A launcher concurrency defect has also been removed. The original launcher checked the PID before manifest/backup work and only published the child PID afterwards, allowing two simultaneous launch requests to race and start two reviewer processes. A deterministic delayed-backup fixture reproduced two application starts. `scripts/launch.sh` and `scripts/sync.sh` now share an atomic operation-lock directory so single-instance startup is serialized through PID publication and sync exclusively owns the collection for its full lifetime.

## Verified VM evidence

Detailed evidence is in:

- `docs/VM_BUILD_20260821.md` — first green semantic/ARMHF/package checkpoint;
- `docs/VM_CONTINUATION_20260821.md` — canonical source cleanup, exact PW6 runtime pin, fresh ARMHF/package rebuild and QEMU status;
- `docs/VM_CONTINUATION_20260822.md` — sync hardening, reviewer runtime fixtures, and deterministic launch/sync lifecycle-race repair.

### Full upstream backend tests

Persisted checkpoint:

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

### Real APKG integration

Five real decks passed the C ABI reviewer lifecycle test:

- `4000 Essential English Words.apkg` — AV observed;
- `Advanced Vocabulary Complete (20 Units).apkg` — typed answer observed;
- `COCA-English.apkg`;
- `新东方 雅思 乱序版.apkg` — AV observed;
- `百词斩考研.apkg` — AV observed.

### 2026-08-22 deterministic sync / reviewer / lifecycle evidence

The sync worker rejects simultaneous `--full-upload` and `--full-download` instead of silently allowing argument order to select a destructive direction. Its deterministic fixture covers required-sync decisions, endpoint/timeout/server-USN propagation, open/sync/full/media errors, credential non-disclosure, and signal-driven `abort -> close -> core_free` shutdown ordering.

Validated exact GitHub blobs:

```text
native/sync.c                     ec6c109f8d331c31aae403b45f9ff09f83272fa8
tests/fake_sync_backend.c         4ea347196aaa6ead68283867fded7fec21dc536c
tests/test_sync_worker.sh         17d4874a12a758f1fac1977a8e3ac20fb41fc95d
```

Result:

```text
test_sync_worker: ok
```

A dependency-free Node/vm fake-DOM harness drives production `web/reviewer.js` through the public `window.kapReviewer` API. Ten fixture groups cover mixed CJK/Latin rendering, card classes/CSS/intervals, typed input, inline-script replacement, desktop replay-control removal, AV marker/replay/TTS routing, nested-scroll flattening, answer separator behavior, state transitions, render/backend errors and touch paging.

Result:

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
```

A deterministic lifecycle regression intentionally delays the pre-open backup, reproducing the former double-launch window. Before the fix, two app processes started. With the shared operation lock, the fixture requires exactly one `start` and one `raised`. It also verifies that launch fails closed while sync holds the lock, that sync releases it on completion/error paths covered by the script, and that a dead owner can be reclaimed.

Current lifecycle blobs validated locally:

```text
scripts/launch.sh                  13bd8618773b0d53b2f92cc9221861629de2adf7
scripts/sync.sh                    6c466df5364cc7ec72a9635fc5ce941080ba41fe
tests/fake_app.c                   3964cbfbe639ea218fe8b538bc734ebbeb32167b
tests/test_lifecycle.sh            5d9ea402c5353aa2ef411e2968b9498c0759383b
```

Result:

```text
test_lifecycle: ok
```

`testenv/scripts/run-static-gates.sh` includes the reviewer runtime fixture and the existing lifecycle/sync fixtures. A complete gate from the final canonical head still must be executed before release provenance is claimed.

### Fresh ARMHF / GLIBC checkpoint

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

The cross-toolchain sysroot ceiling is GLIBC_2.18. The exact extracted PW6 5.19.6 target `libc.so.6` oracle advertises through GLIBC_2.35. The former is intentionally the more conservative build gate; exact dynamic loading against the verified PW6 rootfs remains a separate QEMU gate.

### Fresh audited VM package

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

This archive passes manifest, privacy/state, required-file and ZIP-integrity gates. It is a checkpoint artifact, not the final release, because final provenance must be regenerated from the current canonical GitHub source head and exact-rootfs QEMU/final persistence remain open.

### QEMU

A statically linked ARMHF sanity binary produced by KindleHF executes under QEMU 8.2.2. The toolchain sysroot itself is deliberately not treated as a PW6 runtime replacement: attempting dynamic execution against it triggered an `ld.so` relocation assertion even for a trivial program. The exact-rootfs verifier and smoke harness are therefore required before target-runtime acceptance.

The VM retains exact PW6 firmware/rootfs/runtime oracle reports and hashes but not the complete extracted rootfs bytes; report files are not accepted as a substitute for an actual target rootfs in the dynamic QEMU gate.

## Build strategy after Actions quota exhaustion

- Iterative builds/tests run in the VM/container with prepared offline Rust/Cargo/protoc/KindleHF inputs when available.
- Meaningful source and evidence are written to GitHub immediately.
- `.github/workflows/kindle-anki-port.yml` is maintained as the independent reproducibility definition and consumes the ordinary source tree directly.
- GitHub Actions remains a later independent rerun when quota is available, not the primary development compiler.
- The user's local host is not used for ordinary compilation.

## Current ordered next actions

1. Re-materialize/checkout the then-current canonical GitHub ordinary tree in a build-capable VM and rerun the complete static gate, full rslib, real-APKG, ARMHF and package gates so final provenance points to the canonical source head rather than a prior VM checkpoint.
2. Obtain the exact checksum-verified PW6 5.19.6 rootfs bytes as a private test input, run `verify-pw6-rootfs.py`, then execute backend/audio/sync QEMU smoke.
3. Continue deterministic lifecycle/reviewer/core review for state-machine and collection-ownership failures that do not require target hardware.
4. Persist the final canonical-head `Kindle-Anki-Port-PW6-armhf.zip`, exact SHA-256, package contents, ABI/GLIBC reports and test report durably on GitHub.
5. Begin PW6 hardware-in-the-loop acceptance only after all non-hardware gates above are green and persisted.

## Completion definition

Software release completion requires complete maintainable ordinary source files in GitHub; a green reproducible host and ARMHF build from that canonical source; exact-rootfs QEMU target-runtime smoke evidence; ABI/GLIBC and package-policy audits; and `Kindle-Anki-Port-PW6-armhf.zip` plus SHA-256, manifest, contents and test report persisted on GitHub.

PW6 hardware acceptance is a separate final gate and must be recorded from actual device evidence rather than inferred from VM or CI results.
