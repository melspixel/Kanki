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
- Rootfs helper hardening: `docs/VM_ROOTFS_HELPER_HARDENING_20260822.md`
- Canonical-source audit: `docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md`
- Lifecycle hardening: `docs/VM_LIFECYCLE_HARDENING_20260822.md`, `docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md`
- Package/privacy hardening: `docs/VM_PACKAGE_HARDENING_20260822.md`
- Build provenance hardening: `docs/VM_BUILD_PROVENANCE_HARDENING_20260822.md`
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

These are valid persisted checkpoints, not yet the final canonical-head release provenance; the complete backend/APKG sequence still has to be rerun from the eventual release head.

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

The first lifecycle fix now:

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

Earlier lifecycle checkpoint:

```text
d589345428f28777cf413f97ac0602d565dbfa90
```

See `docs/VM_LIFECYCLE_HARDENING_20260822.md`.

#### 2026-08-22 zombie-owner hardening

The newer pre-publication SIGKILL fixture exposed another real stale-lock state. The gated child correctly exits before it can `exec kap-sync` when its wrapper is killed, but the exited child may remain temporarily as a zombie. Linux `kill -0 <pid>` still succeeds for state `Z`, so the previous stale-owner predicate could treat a dead, collection-free zombie as a live sync owner and return `74` indefinitely in environments where it was not promptly reaped.

The current lifecycle policy now requires:

```text
kill -0 PID succeeds
AND, when /proc/PID/stat is readable, process state != Z
```

This is implemented in both `scripts/launch.sh` and `scripts/sync.sh`; if `/proc/<pid>/stat` is unavailable, behavior safely falls back to the prior `kill -0` check.

Deterministic targeted coverage creates a real unreaped zombie and verifies both launch and sync reclaim it correctly while `kill -0` still succeeds for that PID.

Targeted results:

```text
sh -n scripts/launch.sh                         PASS
sh -n scripts/sync.sh                           PASS
test_zombie_operation_lock.sh                   5/5 PASS
test_sync_wrapper_signal.sh                     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256             2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Canonical blobs:

```text
scripts/launch.sh                   34ee8d5f106e31eb5e78509e1e6054c993bf9711
scripts/sync.sh                     7381fca8bdef86c57c580a367f5647173f76c892
tests/test_zombie_operation_lock.sh 54e3a7c899a69c2fb558b711439b6cb98083284f
```

Material commits:

```text
174d93d37bb78a666aa92eef51029f8555b91501  fix: reclaim zombie sync operation owners
dcb3e2ea9e6e4b175a9d33f21dc4ae90352dda62  fix: reclaim zombie launch operation owners
e4b928e7af7ebd3c7c562c3e23d53f153da0b4f4  test: cover zombie operation-lock owners
ccf259d885e489c766e4656f4d0a6be75f1672ce  test: gate zombie operation-lock recovery
58deb5ded87f30c375d86d696661757dc659d24b  test: keep zombie-lock regression output clean
00fa97ba3b104a85843084f8bc2b7a45d182e089  docs: record zombie operation-lock hardening
```

See `docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md`.

### Build provenance preflight hardening

A release-provenance gap was found in both host-backend and ARMHF entry points. Before this fix, a dirty project tree could be compiled and later cleaned while outputs still claimed the unchanged `HEAD`; separately, a different Anki checkout could be compiled while provenance text still named the lock-file pin.

The host and ARMHF build gates now fail before injection/Cargo when the project is not a clean Git checkout at the declared `BUILD_COMMIT`, or when the Anki checkout base `HEAD` is not exactly the `upstream.lock.json` pin. The ARMHF path also rejects any `ANKI_COMMIT` override that differs from the lock file.

Targeted exact-source fixture results:

```text
test_armhf_provenance.py       6/6 PASS
ARMHF targeted log SHA-256     2ee0b646827cbeb83d05ea7572ad526d914826f4d480b5b485b2633edb17d538
test_host_backend_provenance.py 5/5 PASS
host targeted log SHA-256      897fd9ac46cc311276d31218d58a50cec190cad6582ebc518be803ccf2365db4
```

Current build-gate blobs at the targeted checkpoint:

```text
testenv/scripts/run-armhf-gates.sh        a81e8017034ba707aa0fca93248f44ec6c87dc1b
testenv/scripts/run-host-backend-gates.sh e58c1271f87815221faa5eb165c3fa96acb97df5
```

The new regressions are part of `run-static-gates.sh`. See `docs/VM_BUILD_PROVENANCE_HARDENING_20260822.md` for the exact false-provenance scenarios, commands, exit policy, hashes and commits.

### ARM hard-float checkpoint

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

The exact PW6 5.19.6 runtime oracle advertises through GLIBC_2.35. The build requirements are below that ceiling. A static ARMHF sanity executable runs under QEMU 8.2.2.

These are checkpoint results from the prior canonical build and must be rerun from the final release head. They predate the new source-identity preflight and therefore cannot be promoted to final release provenance without a fresh rebuild.

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

This earlier checkpoint passed its then-current ZIP integrity, internal manifest, required-file and privacy/state gates. It is **not** the final release and is explicitly stale because it predates the latest lifecycle/rootfs-helper/package/build-provenance hardening, the current canonical branch state and exact-rootfs QEMU smoke.

## Exact PW6 runtime and rootfs pipeline

Manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned identities:

```text
firmware version:       5.19.6 / 4832160042
firmware MD5:           697aeb33c02f46b9b0911ab05c28b06d
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

The Python preparation tool verifies firmware SHA-256/MD5, extracts with KindleTool, requires exactly one rootfs image, verifies its SHA-256, uses unprivileged `debugfs rdump`, invokes `verify-pw6-rootfs.py`, records provenance and removes partial output on failure.

Exact tested Git blobs:

```text
prepare-pw6-rootfs.py   dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
test fixture            bd503d5842720c054531b3ca60ec708cd27de0eb
```

Persisted VM result:

```text
python3 tests/test_prepare_pw6_rootfs.py
test_prepare_pw6_rootfs: ok
```

Relevant canonical Python-pipeline commits:

```text
477df23b2db90422660c34309eb8798f0b536e1f  rootfs preparation pipeline
d086bc2c4b22636a76de450735481316cb754b47  rootfs preparation fixture
3be9b9bf72f0a7e88066f0c774caa454b79eeb42  canonical static-gate integration
ef064fe91d618a8f1ac15f70fa68ab7881ffffcf  exact fixture-source alignment
52928234fe776f5b52fb4b0e0b5b95bdd3e2aff2  VM evidence report
```

### 2026-08-22 shell acquisition helper audit

A shell convenience helper was added at `testenv/scripts/prepare-pw6-rootfs.sh`, then audited before it was accepted as a gated path. Its initial version had four defects:

- read the non-existent manifest key `firmware.package_sha256` instead of `firmware.sha256`;
- omitted the pinned firmware MD5 check;
- its test attempted direct execution while the Git file mode was `100644`;
- automatic fallback broadened provenance to a community mirror.

The corrected helper now:

- reads `firmware.sha256`, `firmware.md5` and `rootfs_image.sha256` from the canonical manifest;
- validates both SHA-256 and MD5 before external tools run, including the temporary download before it is moved into place;
- automatically downloads only from the official Amazon alias and pinned Amazon S3 object;
- is stored with executable mode `100755` while its regression invokes it through `sh` so the test does not depend on mode preservation;
- is included in `run-static-gates.sh` with syntax and Python fixture checks.

Canonical identities:

```text
testenv/scripts/prepare-pw6-rootfs.sh  d01b1d02ced887592926deb5de586b6f40a0a3f0  mode 100755
tests/test_rootfs_prepare_script.py    d7399aa70688b6128c61a916ff9dd8e758de94f3
testenv/scripts/run-static-gates.sh    0c79c69f57f9506d6a2239e76cb4ee767476fcec
```

Targeted helper validation:

```text
sh -n testenv/scripts/prepare-pw6-rootfs.sh       PASS
python3 tests/test_rootfs_prepare_script.py       Ran 3 tests in 6.816s; OK
```

Content SHA-256 values of the targeted reconstruction:

```text
prepare-pw6-rootfs.sh         ca191215e97cc75d3945531c370e47d769ede74513fa44caf3a140d0744829bc
test_rootfs_prepare_script.py c5cdfc42e7de248ba90f0ffda1a71cfbb93df14c1894ed4068bb021b05e18500
```

Material helper commits:

```text
32b166ca650b04086f970e0b92d83a602f7b879e  testenv: add reproducible PW6 firmware-to-rootfs preparation
e4103bc5fb3c65d75c4bb22b5c4ca5358a9b8320  test: validate pinned PW6 rootfs preparation helper
cea5f6ae0be998f0426292a2da0f38a706d9fb2d  fix: correct pinned PW6 firmware helper verification
1c59968cd8af1fc4182a51c59e6c31562dc94597  test: enforce PW6 helper hashes and shell invocation
b1ed8a74d289ee0cf37005d924392a0352ebe8c6  test: gate PW6 firmware helper validation
335817498abaebe8f14a6454ffcf4e7f303e5be5  testenv: mark PW6 rootfs helper executable
cb5ddf7adaa022b07f2f16c121297361da25ba44  docs: record executable PW6 helper fix
```

See `docs/VM_ROOTFS_HELPER_HARDENING_20260822.md`.

The exact-rootfs QEMU gate is still pending the external checksum-matching firmware/rootfs bytes. Derived oracle reports and checksum metadata are not accepted as substitutes for running against the actual rootfs.

## 2026-08-22 continuation checkpoint

Coordination/progress state immediately before this handoff update was persisted through:

```text
a387f5409110b423bf6389c92434e593fa5fc512  docs: refresh Codex boundary and rootfs task
```

This continuation did **not** claim a fresh full canonical-head build. The isolated execution environment used for the targeted lifecycle/helper/provenance work could not resolve external Git/HTTP hosts for a normal clone/fetch, so it was not a valid place to re-run the complete pinned Anki/toolchain build. Ordinary compilation remains VM-owned; it is not delegated to the user.

What is green from the latest provenance continuation is limited to the targeted host/ARMHF source-identity regressions documented above. The next build VM must materialize the latest branch head and run the complete sequence before any new package can become release evidence.

## Current ordered next actions

1. Materialize the then-current canonical `kindle-anki-port` branch head in a build VM with the pinned Anki checkout and toolchain cache.
2. Run the complete static gate from that clean head, including the zombie-lock, rootfs-helper, package-provenance, ARMHF-provenance and host-backend-provenance regressions.
3. Run the full non-hardware build/test sequence from the same commit:

   ```text
   full official rslib tests
   five-real-APKG integration
   run-armhf-gates.sh
   ABI/GLIBC audit
   package-and-audit.sh
   ```

4. Obtain the checksum-matching PW6 5.19.6 firmware/rootfs as a private input and run:

   ```text
   prepare-pw6-rootfs.py
   verify-pw6-rootfs.py
   run-qemu-smoke.sh
   ```

   `CODEX_COORDINATION.md` Task B is the only current local/Codex task that may be claimed, and only for supplying the verified private rootfs input. Compilation, QEMU execution and packaging remain VM-owned.
5. Regenerate the final installer from the exact canonical source commit that passed all non-hardware gates.
6. Persist `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, package listing, build provenance, ABI/GLIBC report and complete test report durably on GitHub.
7. Only after those artifacts are final may the physical-PW6 hardware task begin. Record HIL separately; never convert QEMU results into a device PASS.

## Local-host boundary

The user's Mac is not required for ordinary compilation. It is only a bridge for private runtime bytes or the physical Kindle when USB/USBNetwork/SSH or irreducibly physical actions are required. `CODEX_COORDINATION.md` defines the exact private-rootfs and hardware report formats. No local-host compilation task is requested.

## Release record

Not released.

Current release blockers:

- complete reproducible static/backend/APKG/ARMHF/package rerun from the latest canonical GitHub head, now including fail-closed project/Anki source-identity preflight;
- exact-rootfs dynamic QEMU smoke against checksum-matching PW6 5.19.6 bytes;
- regenerated final package with fresh SHA-256/manifest/contents/audit reports persisted durably on GitHub;
- separately recorded physical PW6 acceptance.

## Integrity rule

Do not mark the project complete merely because a ZIP exists in a VM. Completion requires a reproducible green build from the current canonical source, exact-rootfs QEMU evidence, package/ABI audits, durable GitHub release persistence and a separately recorded real-PW6 acceptance result.
