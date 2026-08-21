# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1)
- Phase summary: `PROGRESS.md`
- Architecture/source map: `docs/ARCHITECTURE.md`, `docs/SOURCE_MAP.md`
- Test design: `docs/TEST_ENVIRONMENT.md`
- Local/Codex coordination: `CODEX_COORDINATION.md`

Current detailed continuation reports include:

```text
docs/VM_BUILD_20260821.md
docs/VM_CONTINUATION_20260821.md
docs/VM_CONTINUATION_20260822.md
docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md
docs/VM_LIFECYCLE_HARDENING_20260822.md
docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md
docs/VM_ROOTFS_PIPELINE_20260822.md
docs/VM_ROOTFS_HELPER_HARDENING_20260822.md
docs/VM_PACKAGE_HARDENING_20260822.md
docs/VM_BUILD_PROVENANCE_HARDENING_20260822.md
docs/VM_QEMU_PROVENANCE_HARDENING_20260822.md
docs/VM_PACKAGE_QEMU_BINDING_20260822.md
```

This file is the authoritative continuation point and must stay synchronized after material source, build, QEMU, package, or release changes.

## Non-negotiable project boundary

This is an independent Kindle platform port of desktop Anki, not a Ranki patch set.

- Official Anki `rslib` owns collection, scheduling, rendering, typed-answer comparison, media, sync and undo.
- The Kindle frontend communicates through a named semantic C ABI.
- Production contains no Ranki, `rewrite-v1`, `LD_PRELOAD`, deck-name checks or note-type-specific CSS patches.
- GTK/WebKit, e-ink, focus, touch, keyboard, audio and lifecycle are Kindle platform responsibilities only.
- VM/QEMU/mocks can close non-hardware gates but cannot constitute PW6 hardware acceptance.

## Completion definition

Software delivery is not complete until all of the following are true from one current clean canonical source identity:

1. ordinary maintainable source is complete and persisted in GitHub;
2. host/backend tests are green against the pinned official Anki 26.08.1 checkout;
3. five representative real APKG integrations are green;
4. ARMv7 hard-float build, ABI and GLIBC audits are green;
5. exact checksum-matching PW6 5.19.6 rootfs QEMU smoke is green for the exact ARMHF bytes being released;
6. package/privacy/provenance audits are green;
7. `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, contents, ARMHF/QEMU/package provenance and complete reports are persisted durably on GitHub.

Physical PW6 acceptance is a separate final gate and must be recorded from real-device evidence.

## Current implementation

The independent port is ordinary source under `kindle-anki-port/`. The maintained implementation includes:

- `core/src/port.rs` — semantic C ABI and reviewer state;
- `core/src/services_bridge.rs` — narrow backend-owned bridge beneath official generated Anki services;
- `native/app.c` — Kindle native host;
- `native/audio.c` — GStreamer/`mixersink` audio worker;
- `native/sync.c` — collection/full/media sync worker;
- `web/` — persistent ES5 reviewer/compatibility layer;
- `scripts/launch.sh`, `scripts/sync.sh` — lifecycle and collection ownership;
- `tests/`, `testenv/` — deterministic semantic/lifecycle/package/QEMU/ARM gates.

`docs/VM_CANONICAL_SOURCE_AUDIT_20260822.md` records PASS for ordinary-source build/package independence: maintained project inputs resolve from `kindle-anki-port/` plus explicitly pinned Anki/Rust/KindleHF inputs.

## Persisted semantic/backend checkpoint

The former 26-error Anki Rust visibility blocker was resolved by injecting `services_bridge.rs` beneath Anki's generated `services` module and exposing only the narrow `pub(crate)` operations required by the C ABI.

Persisted checkpoint:

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

Five real APKG fixtures passed open/deck/queue/question/reveal/rate/close through the C ABI. Typed-answer behavior was observed on the Advanced Vocabulary fixture; AV packets were observed on three fixtures.

These remain valid historical checkpoints but are not final release provenance because newer lifecycle/build/QEMU/package hardening changed the canonical head. They must be rerun from the final clean release commit.

## Reviewer, sync and lifecycle checkpoint

Persisted deterministic coverage includes:

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
test_sync_worker: ok
```

Coverage includes persistent reviewer DOM/classes/scripts, typed input, AV/replay/TTS routing, CSS compatibility, long-page paging, sync decisions/full-sync conflicts, endpoint/timeout/server-USN propagation, error cleanup, credential non-disclosure, and `abort -> close -> core_free` shutdown ordering.

A real sync-wrapper termination defect was reproduced and fixed: the actual `kap-sync` worker now owns the shared collection-operation lock, wrapper TERM/INT/HUP is forwarded, conventional signal statuses are propagated, and wrapper SIGKILL cannot make a still-running sync worker appear absent.

A later pre-publication SIGKILL test exposed a zombie-owner edge case: Linux `kill -0` succeeds for an unreaped state-`Z` process. `scripts/launch.sh` and `scripts/sync.sh` now use a zombie-aware liveness predicate and reclaim such dead owners.

Targeted lifecycle evidence:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=no
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Current lifecycle blobs:

```text
scripts/launch.sh                    34ee8d5f106e31eb5e78509e1e6054c993bf9711
scripts/sync.sh                      7381fca8bdef86c57c580a367f5647173f76c892
tests/test_zombie_operation_lock.sh 54e3a7c899a69c2fb558b711439b6cb98083284f
```

See `docs/VM_LIFECYCLE_HARDENING_20260822.md` and `docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md`.

## Build-source provenance hardening

Host-backend and ARMHF entry points now fail before injection/Cargo unless:

```text
PROJECT HEAD == declared BUILD_COMMIT
PROJECT subtree is clean, including untracked source
ANKI HEAD == upstream.lock.json commit
ARMHF ANKI_COMMIT override, if present, == upstream.lock.json commit
```

Targeted fixture results:

```text
test_armhf_provenance.py         6/6 PASS
ARMHF targeted log SHA-256       2ee0b646827cbeb83d05ea7572ad526d914826f4d480b5b485b2633edb17d538
test_host_backend_provenance.py  5/5 PASS
host targeted log SHA-256        897fd9ac46cc311276d31218d58a50cec190cad6582ebc518be803ccf2365db4
```

Current checkpoint blobs:

```text
testenv/scripts/run-armhf-gates.sh        a81e8017034ba707aa0fca93248f44ec6c87dc1b
testenv/scripts/run-host-backend-gates.sh e58c1271f87815221faa5eb165c3fa96acb97df5
```

See `docs/VM_BUILD_PROVENANCE_HARDENING_20260822.md`.

## ARM hard-float / ABI checkpoint

Historical checkpoint:

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

The pinned PW6 5.19.6 target libc advertises through GLIBC_2.35, so the checkpoint requirements are under the target ceiling. This must still be regenerated from the final clean release head.

## Exact PW6 5.19.6 runtime pipeline

Canonical manifest:

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

The Python preparation pipeline verifies firmware SHA-256/MD5, rootfs-image SHA-256, extracts with KindleTool/debugfs, invokes the canonical verifier, records provenance, and removes partial output on failure.

The shell acquisition helper is also gated. Its corrected form reads the real manifest keys, validates both firmware SHA-256 and MD5 before extraction, uses only official Amazon automatic sources, and is stored executable.

Current identities:

```text
testenv/scripts/prepare-pw6-rootfs.py  dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
tests/test_prepare_pw6_rootfs.py        bd503d5842720c054531b3ca60ec708cd27de0eb
testenv/scripts/prepare-pw6-rootfs.sh  d01b1d02ced887592926deb5de586b6f40a0a3f0  mode 100755
tests/test_rootfs_prepare_script.py    d7399aa70688b6128c61a916ff9dd8e758de94f3
```

The exact checksum-matching firmware/rootfs bytes are still not mounted in the current VM. Oracle reports or checksum metadata are not substitutes for running against the actual rootfs.

See `docs/VM_ROOTFS_PIPELINE_20260822.md` and `docs/VM_ROOTFS_HELPER_HARDENING_20260822.md`.

## Exact-rootfs QEMU provenance hardening

`run-qemu-smoke.sh` now requires:

```text
clean PROJECT at BUILD_COMMIT
ARMHF-GATES.txt == "ARMHF gates: PASS"
ARMHF source_commit == BUILD_COMMIT
ARMHF anki_commit == pinned Anki commit
ROOTFS_MANIFEST bytes == committed PW6 5.19.6 manifest
```

It persists rootfs verification, backend/audio/sync smoke logs, source/Anki identity, canonical manifest SHA-256, and all four ARMHF binary hashes.

The latest hardening also sanitizes `QEMU-PROVENANCE.txt`: absolute rootfs/manifest paths are no longer persisted. Stable fields include:

```text
rootfs_manifest_id=pw6-5.19.6-rootfs-manifest.json
rootfs_manifest_sha256=<sha256>
rootfs_verified=true
```

Current blobs:

```text
testenv/scripts/run-qemu-smoke.sh  ac595dbeb6c411b51751953eef9b9400afe5a166
tests/test_qemu_provenance.py      c3ccf143be655f2638770b5c5ea7f012d384c037
```

The prior six-case QEMU provenance fixture was green; the current path-sanitization change was additionally exercised with a synthetic QEMU fixture that confirmed a successful PASS and absence of the private rootfs absolute path.

See `docs/VM_QEMU_PROVENANCE_HARDENING_20260822.md` and `docs/VM_PACKAGE_QEMU_BINDING_20260822.md`.

## Package/privacy/provenance hardening

The package auditor rejects transient or user state, including:

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

The package script already required current ARMHF `source_commit`, pinned `anki_commit`, and `ARMHF gates: PASS`.

The newest release-boundary fix closes the remaining gap between QEMU and packaging: `package-and-audit.sh` now requires a `QEMU` evidence directory from `run-qemu-smoke.sh` and refuses packaging unless all of these match the release being archived:

```text
QEMU-SMOKE.txt == "QEMU smoke: PASS"
rootfs-verification contains "PW6 rootfs verification: PASS"
backend/audio/sync smoke markers are PASS
QEMU source_commit == package BUILD_COMMIT
QEMU anki_commit == pinned Anki commit
QEMU rootfs_manifest_sha256 == committed canonical manifest SHA-256
QEMU hashes for libanki-kindle.so/kap-app/kap-audio/kap-sync == actual ARMHF bytes
```

Successful packaging now persists the QEMU smoke/provenance/rootfs/backend/audio/sync reports in the release directory and records `rootfs_manifest_sha256` plus `qemu_provenance_sha256` in `PACKAGE-PROVENANCE.txt`.

Current blobs:

```text
testenv/scripts/package-and-audit.sh   930a4128adf6e754f58a7f55da8014e59b90b122
tests/test_package_reproducibility.py  9b85781c6a4738b117da5ff218276c373089aa55
```

Targeted isolated evidence:

```text
matching ARMHF + matching QEMU provenance   rc=0
stale QEMU source_commit                    rc=66
stale QEMU kap-app hash                     rc=66
QEMU-SMOKE.txt = FAIL                       rc=66
synthetic ZIP SHA-256                       1d518583b1bae606885be4873bc3fa1528f826ac0ab77fd9453d8b676e5fa067
KAP_PACKAGE_QEMU_BINDING_20260822.log SHA-256
97fa62623ae4e940f8963b2bc3e15649306f413bbf441411dc950ca61af2e9be
```

The synthetic ZIP is test evidence only.

Detailed report: `docs/VM_PACKAGE_QEMU_BINDING_20260822.md`.

## Stale package checkpoint

An earlier audited package exists:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256: 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It is explicitly stale. It predates the latest lifecycle/rootfs-helper/build/QEMU/package-provenance hardening and cannot pass the current package gate because it is not bound to fresh exact-rootfs QEMU evidence for the current release bytes.

Do not publish or relabel this checkpoint as final.

## Current execution-environment limitation

The direct continuation container still cannot resolve `github.com` for a normal Git clone/fetch. Latest probe:

```text
git clone --branch kindle-anki-port --single-branch https://github.com/melspixel/Kanki.git /tmp/Kanki
rc=128
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
```

Therefore this continuation did not claim a fresh full canonical-head static/backend/Anki/ARMHF build. Targeted synthetic fixtures were used only where they exercise the changed production predicates directly. Ordinary compilation remains VM-owned and is not delegated to the user.

## Latest material commits

The package/QEMU binding continuation added:

```text
a974f87f57ac83dd7ef3e042f9866b1c5aa7fc22  fix: sanitize exact-rootfs QEMU provenance
ae94c42917e73a438232474276ff2ae15523e37e  fix: require exact-rootfs QEMU evidence for release packaging
7c61902cc9f5025569a146fb89ac1d1a845efcf6  test: bind package reproducibility to QEMU provenance
7b65b0ba32642d4c77d665a6e9d39d242dcbfbb4  test: keep QEMU provenance path-sanitized
5014ce83c3d6d0e63e87af8c12e9b803f7458e85  test: persist package QEMU binding evidence
24f60693da51565847e81edb9609e831333a40bf  docs: record package QEMU release binding hardening
afefcb8322ceca1f739fc5a5eead4b3e177090fe  docs: update progress for package QEMU binding
```

The current handoff update follows those commits; always re-read the branch head before building.

## Ordered next actions

1. Materialize the then-current `kindle-anki-port` branch head in a network-capable build VM with the pinned Anki checkout and KindleHF/toolchain inputs.
2. Run the complete static gate from that clean head, including lifecycle/zombie-lock, rootfs-helper, build provenance, QEMU provenance and package/QEMU-binding regressions.
3. From the same clean commit and exact Anki 26.08.1 checkout, rerun:

   ```text
   full official rslib tests
   five-real-APKG integration
   host release backend build/export audit
   run-armhf-gates.sh
   ARM ELF/ABI/GLIBC audit
   ```

4. Obtain the checksum-matching PW6 5.19.6 firmware/rootfs as a private input and run:

   ```text
   prepare-pw6-rootfs.py
   verify-pw6-rootfs.py
   run-qemu-smoke.sh
   ```

   The QEMU gate must consume the fresh ARMHF outputs from step 3.
5. Only after that exact-rootfs QEMU PASS, run:

   ```text
   QEMU=<fresh qemu output> package-and-audit.sh
   ```

   The current package gate will reject absent, stale, wrong-source, wrong-Anki, wrong-manifest or wrong-binary QEMU evidence.
6. Persist the final `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, package contents, ARMHF/ABI/GLIBC reports, QEMU/rootfs logs, package provenance and complete test report durably on GitHub.
7. Only after all non-hardware artifacts are final may the PW6 hardware-in-the-loop task begin. Record hardware acceptance separately and never infer it from QEMU.

## Local-host / Codex boundary

The user's local host is not required for ordinary compilation. It may only be used as a bridge for private target runtime bytes or the physical Kindle when the VM cannot access them directly.

`CODEX_COORDINATION.md` Task B remains the only currently useful pre-release local/Codex task: supply the checksum-verified PW6 5.19.6 private rootfs input. Compilation, QEMU execution and packaging remain VM-owned.

## Release record

Not released.

Current release blockers:

- complete reproducible static/backend/APKG/ARMHF rerun from the latest canonical GitHub head;
- exact-rootfs dynamic QEMU smoke against checksum-matching PW6 5.19.6 bytes and the fresh ARMHF outputs;
- regenerated final package through the new QEMU-bound package gate, with fresh SHA-256/manifest/contents/reports persisted durably on GitHub;
- separately recorded physical PW6 acceptance.

Do not mark the project complete merely because a ZIP exists in a VM. Completion requires one clean release provenance chain from source -> Anki pin -> ARMHF bytes -> exact PW6 rootfs QEMU -> package -> durable GitHub artifacts, plus a separate real-PW6 acceptance result.
