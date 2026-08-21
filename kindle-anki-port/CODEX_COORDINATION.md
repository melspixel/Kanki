# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-22 UTC

## Purpose

This is the only coordination surface for work that genuinely requires a local/Codex worker. Read `HANDOFF.md`, `PROGRESS.md`, `docs/TEST_ENVIRONMENT.md`, and `VM_RUNBOOK.md` first.

Do not import Ranki, `rewrite-v1`, historical card-template patches, preload runtimes, or local scheduler/renderer reimplementations into the independent port.

## Current status

The ordinary independent source tree is fully materialized in GitHub. Historical checkpoints include the full official Anki backend suite (`539 passed; 0 failed`), five real APKG C-ABI integrations, ARMHF hard-float build/ABI evidence, deterministic reviewer/sync/lifecycle tests, and an older audited ZIP.

The old ZIP SHA-256

```text
9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

is stale and must not be published as final.

The current release chain is fail-closed:

```text
clean current source
-> official Anki 26.08.1 semantic/backend tests
-> five real APKG integrations including typed-answer coverage
-> ARMHF + ABI/GLIBC/export audit
-> exact checksum-matching PW6 5.19.6 rootfs QEMU
-> QEMU-bound package/privacy/reproducibility audit
-> final ZIP/SHA-256/manifest/contents/reports persisted on GitHub
```

`package-and-audit.sh`, the top-level Makefile, `vm-advance.py`, public GitHub Actions policy, `docs/TEST_ENVIRONMENT.md`, and `testenv/README.md` now all encode QEMU-before-package ordering. Public CI intentionally emits only a `NOT-A-RELEASE.txt` host/ARMHF checkpoint because the private PW6 rootfs is not stored in GitHub.

The direct VM used by the current continuation cannot resolve `github.com` through normal Git DNS, and the checksum-matching private PW6 rootfs is not mounted. Those are current environmental blockers, not a reason to move ordinary compilation onto the user's host.

## Canonical pins

```text
official Anki commit    e5a6fbe27fdd4d57d5f712191b4a753032e57853
Anki release            26.08.1
Rust target             armv7-unknown-linux-gnueabihf
Kindle GCC triple       arm-kindlehf-linux-gnueabihf
koxtoolchain            2025.05
PW6 firmware            5.19.6 / 4832160042
```

Exact PW6 hashes are committed in `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`.

## Responsibility boundary

### VM-owned work

The VM owns ordinary compilation and all software release work:

- source edits/code generation;
- official Anki Rust/C ABI work;
- host semantic/unit/integration tests;
- five-real-APKG testing;
- ARMHF cross-compilation;
- ELF/ABI/GLIBC/export audits;
- exact-rootfs QEMU once the private rootfs is available;
- mocked Kindle-service tests;
- package construction/privacy/reproducibility audit;
- GitHub source/log/report/final-artifact persistence.

The user's local host is **not** a compiler requirement.

### Local/Codex work

A local/Codex worker may be used only when the VM cannot directly obtain a private target input or cannot directly communicate with the physical Kindle.

Before software release, the only currently useful local task is transporting the checksum-verified PW6 5.19.6 private rootfs. After software release, the local host may bridge physical HIL over USB/USBNetwork/SSH.

No local worker may replace the VM release build with its own ordinary compile.

## Current evidence

```text
official Anki rslib historical checkpoint: 539 passed; 0 failed
five real APKG integrations: historical PASS
reviewer fixture groups: 10 PASS
test_sync_worker: PASS
test_zombie_operation_lock.sh: 5/5 PASS
test_sync_wrapper_signal.sh: 3/3 PASS
zombie evidence SHA-256:
  2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
package/QEMU targeted evidence SHA-256:
  97fa62623ae4e940f8963b2bc3e15649306f413bbf441411dc950ca61af2e9be
exact-rootfs dynamic QEMU: pending actual checksum-matching private rootfs
```

Historical green results must be rerun from the eventual final clean source head; they are not current-head release provenance.

## Requests a Codex/local worker may take

A worker must append a dated claim under **Worker log** before performing a task.

### Task A — canonical-source independent verification

Input:

- current `melspixel/Kanki:kindle-anki-port` branch;
- `kindle-anki-port/` ordinary source;
- `.github/workflows/kindle-anki-port.yml`.

Task:

- verify all maintained build/package inputs resolve from ordinary `kindle-anki-port/` plus explicitly pinned public upstream/toolchain inputs;
- verify no split archive/`part-*`/overlay/legacy Ranki source is needed;
- verify public workflow produces only a non-release checkpoint unless exact private PW6 runtime input is explicitly available outside GitHub.

Output:

- sanitized report with source commit, files inspected, exact commands and PASS/defects.

Acceptance:

- no hidden historical source dependency and no final package path that bypasses exact-rootfs QEMU.

### Task B — exact PW6 5.19.6 rootfs private input — READY IF A NETWORKED WORKER IS AVAILABLE

This task **does not compile the project**. It supplies only the checksum-verified private runtime bytes the VM currently lacks.

Pinned firmware record:

```text
version                     5.19.6
version code                4832160042
official Amazon alias       https://www.amazon.com/update_KindlePaperwhite_12th_Gen_2024
official Amazon object      https://s3.amazonaws.com/firmwaredownloads/update_kindle_all_new_paperwhite_12th_5.19.6.bin
expected firmware MD5       697aeb33c02f46b9b0911ab05c28b06d
expected firmware SHA-256   72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
expected rootfs SHA-256     b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

Required worker procedure:

1. Check out the then-current `kindle-anki-port` branch and record the full commit SHA.
2. Download only from the official Amazon alias/direct object above.
3. Prefer the maintained helper:

   ```sh
   testenv/scripts/prepare-pw6-rootfs.sh \
     --download \
     --firmware <PRIVATE_DIR>/update_kindle_all_new_paperwhite_12th_5.19.6.bin \
     --output <PRIVATE_DIR>/pw6-5.19.6-rootfs \
     --keep-image
   ```

4. The helper must verify both pinned firmware SHA-256 and MD5 before extraction. If manual extraction is unavoidable, verify both hashes first and then use the canonical Python preparation/verifier path.
5. Verify rootfs image SHA-256 exactly matches the value above.
6. Run:

   ```sh
   python3 testenv/scripts/verify-pw6-rootfs.py \
     <PRIVATE_DIR>/pw6-5.19.6-rootfs \
     --rootfs-image <PRIVATE_DIR>/pw6-rootfs.img
   ```

7. Make the extracted rootfs bytes available to the VM through an approved private/mounted channel. Never commit firmware/rootfs/proprietary libraries to GitHub.
8. Commit only a sanitized verification report containing source commit, tool versions, exact commands, firmware SHA-256/MD5, rootfs-image SHA-256, canonical manifest SHA-256 and final verifier result.

Acceptance criteria:

```text
/lib/ld-linux-armhf.so.3 SHA-256
  a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
/lib/libc.so.6 SHA-256
  5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
/usr/lib/libwebkitgtk-1.0.so.0.7.2 SHA-256
  6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max = 2.35
verify-pw6-rootfs.py final marker = PW6 rootfs verification: PASS
```

Output to VM/private channel:

```text
<PRIVATE_DIR>/pw6-5.19.6-rootfs/
<PRIVATE_DIR>/pw6-rootfs.img    # if retained
sanitized GitHub verification report only
```

Never include device serials, credentials, Wi-Fi state or user content.

After Task B succeeds, the VM—not the local worker—must run fresh ARMHF/exact-rootfs QEMU and the QEMU-bound package gate.

### Task C — independent package/lifecycle audit

Input:

```text
native/app.c
native/audio.c
native/sync.c
scripts/launch.sh
scripts/sync.sh
packaging/
testenv/scripts/package-and-audit.sh
testenv/scripts/run-qemu-smoke.sh
testenv/scripts/vm-advance.py
relevant tests
```

Audit specifically:

- launch/raise/exit and stale/dead/zombie owner handling;
- collection-operation lock TOCTOU and signal cleanup;
- live sync owner refusal behavior;
- launcher-triggered sync followed by relaunch;
- Bluetooth route cleanup;
- credentials/transient-state exclusion;
- QEMU source/Anki/manifest/binary-hash binding;
- package-before-QEMU bypasses in every maintained entrypoint.

Output:

- source-commit-pinned sanitized report with exact file/line defects or PASS.

Acceptance:

- no final package path bypasses exact-rootfs QEMU and no historical runtime dependency reappears.

Do not mark the project complete.

### Task D — hardware-in-the-loop bridge

Do not begin until `HANDOFF.md` records a **final GitHub-persisted software-release** installer SHA-256 and test-bundle/report hashes.

Input:

- final installer from GitHub;
- recorded checksums;
- physical jailbroken PW6;
- HIL agent/scripts.

Procedure:

- verify checksums;
- back up `/mnt/us/anki_data`;
- install package/test agent;
- run automated USBNetwork/SSH tests where possible;
- ask the user only for irreducibly physical actions such as hearing audio, touch/IME, Bluetooth pairing and power-button/suspend behavior;
- sanitize all logs before GitHub persistence.

Expected report bundle:

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

Never include AnkiWeb keys, collection/media contents, device serials, Wi-Fi data or unsanitized logs.

## Worker log

Format:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex/local task is currently claimed.

## Current assignment

No local-host compilation action is requested. Task B may be claimed solely to transport the exact verified PW6 5.19.6 private rootfs. All actual compile/QEMU/package work remains VM-owned.

## Completion semantics

A Codex/local worker must never mark the project complete itself.

**Software delivery completion** is recorded in `HANDOFF.md` only after the current clean ordinary source, full host/backend/APKG tests, ARMHF/ABI/GLIBC, exact-rootfs QEMU, QEMU-bound package audit, final ZIP/SHA-256/manifest/contents and complete reports are all durably persisted on GitHub.

**PW6 hardware acceptance is separate.** It begins only after software delivery is complete and must be recorded as a distinct HIL result. A VM/QEMU PASS cannot substitute for it, and a pending HIL result does not retroactively turn a fully persisted software build into an incomplete software artifact.
