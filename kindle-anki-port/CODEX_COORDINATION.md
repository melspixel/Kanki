# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-22 UTC

## Purpose

This file is the asynchronous coordination surface between VM-side porting work and any Codex/local-machine worker. Read `HANDOFF.md`, `PROGRESS.md`, `docs/VM_BUILD_20260821.md`, `docs/VM_CONTINUATION_20260821.md`, `docs/VM_CONTINUATION_20260822.md`, and `docs/TEST_ENVIRONMENT.md` first. Do not import code from Ranki, `rewrite-v1`, historical card-template patches or preload runtimes into the independent port.

## Current constraints and status

GitHub Actions runtime is exhausted. Iterative builds run in the isolated Linux VM/container and all meaningful source, scripts, diagnostics, checksums, reports and final binaries must be persisted back to `melspixel/Kanki:kindle-anki-port`.

The ordinary independent source tree is materialized in GitHub and obsolete split archive staging has been removed. Host semantic evidence, five real-APKG C-ABI integrations, an ARMHF checkpoint, package audit, QEMU static ARM sanity and an exact PW6 5.19.6 runtime manifest are present. The 2026-08-22 continuation additionally hardened sync decisions/error cleanup, repaired launcher/sync collection ownership with a shared atomic operation lock, closed wrapper-SIGKILL and zombie-owner stale-lock windows, and hardened the PW6 firmware acquisition helper so it verifies the manifest's real SHA-256/MD5 keys and uses only official Amazon automatic sources.

Remaining non-hardware work is primarily a full rebuild from the then-current canonical source head, exact-rootfs QEMU execution, further deterministic state/lifecycle review where useful, and final binary/report persistence.

## Canonical pins

- Official Anki: `ankitects/anki@e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Kindle toolchain target: `armv7-unknown-linux-gnueabihf`
- Kindle GCC triple: `arm-kindlehf-linux-gnueabihf`
- koxtoolchain release: `2025.05`
- Target: PW6 / Bellatrix4, firmware 5.19.6 / version code `4832160042`

## Responsibility boundary

### VM-owned work

The VM remains responsible for canonical source rebuilds, official Anki semantic Rust/C ABI work, host unit/integration tests, ARMHF cross-compilation, ELF/ABI/GLIBC audits, QEMU/sysroot smoke tests after a verified rootfs is available, mocked Kindle-service tests, package construction/privacy audit, and GitHub source/report/final-artifact persistence.

The local host is **not required for ordinary compilation**.

### Local-host / physical-Kindle work

The local host is needed only as a bridge for private target inputs or when the VM cannot reach the actual Kindle over USB/USBNetwork/SSH. Physical-device evidence includes real e-ink refresh/ghosting/latency, touch/keyboard behavior, Amazon framework focus/re-entry, Bluetooth audible rerouting, suspend/resume, Wi-Fi/USB mode, memory pressure and repeated relaunch.

These are hardware-in-the-loop tests, not compilation prerequisites.

## Current evidence

- full official Anki rslib persisted checkpoint: `539 passed; 0 failed`;
- five real APKG C-ABI reviewer fixtures pass;
- sync decision/error/shutdown deterministic fixture: pass;
- reviewer public-API runtime fixture matrix: `10` groups pass;
- double-launch defect: reproduced before repair; deterministic one-start/one-raise regression passes after repair;
- launch/sync exclusive collection operation lock and stale-lock recovery: deterministic lifecycle fixture pass;
- pre-publication wrapper-SIGKILL zombie-owner defect: reproduced and fixed; `test_zombie_operation_lock.sh` passed `5/5`, `test_sync_wrapper_signal.sh` passed `3/3` in targeted execution;
- zombie-hardening evidence log SHA-256: `2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250`;
- PW6 shell helper targeted suite: `3` tests pass; helper blob `d01b1d02ced887592926deb5de586b6f40a0a3f0`, mode `100755`;
- fresh `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` checkpoint: ARM EABI5 hard-float;
- cross-toolchain sysroot ceiling: GLIBC_2.18;
- exact PW6 5.19.6 target libc ceiling: GLIBC_2.35;
- audited VM package SHA-256: `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225` (**stale checkpoint only**);
- QEMU 8.2.2 static ARM sanity: pass;
- exact-rootfs dynamic QEMU: pending complete checksum-matching rootfs bytes.

Detailed current reports:

```text
docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md
docs/VM_ROOTFS_HELPER_HARDENING_20260822.md
```

## Requests a Codex worker may take

Only claim a task by appending a dated entry under **Worker log** before editing or transporting private inputs.

### Task A — canonical-source independent verification

Compare materialized `kindle-anki-port/` source at the current branch head with files consumed by `.github/workflows/kindle-anki-port.yml`. Verify that no `part-*`, restore archive or `kindle-anki-port-overlay` input is required, and that legacy root `src/`, `scripts/`, `tools/` are not package inputs. Output a sanitized report; do not change the Anki pin.

Acceptance: build inputs resolve entirely from ordinary `kindle-anki-port/` plus explicitly pinned public upstream/toolchain sources.

### Task B — exact PW6 5.19.6 rootfs private input — READY IF A NETWORKED WORKER IS AVAILABLE

This task does **not** compile the project. It only supplies a checksum-verified private runtime input that the VM currently cannot download because its package/network DNS is restricted.

Input firmware record:

```text
version:                  5.19.6
version code:             4832160042
official Amazon alias:    https://www.amazon.com/update_KindlePaperwhite_12th_Gen_2024
official Amazon object:   https://s3.amazonaws.com/firmwaredownloads/update_kindle_all_new_paperwhite_12th_5.19.6.bin
expected firmware MD5:    697aeb33c02f46b9b0911ab05c28b06d
expected firmware SHA256: 72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
expected rootfs SHA256:   b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

Expected runtime-file hashes are committed in:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Required worker procedure:

1. Check out the then-current `kindle-anki-port` branch head and record its commit SHA.
2. Download only from the official Amazon alias/direct object above. The current helper may be used:

   ```sh
   testenv/scripts/prepare-pw6-rootfs.sh \
     --download \
     --firmware <PRIVATE_DIR>/update_kindle_all_new_paperwhite_12th_5.19.6.bin \
     --output <PRIVATE_DIR>/pw6-5.19.6-rootfs \
     --keep-image
   ```

   The helper must report the pinned SHA-256 and MD5 before KindleTool/debugfs extraction. If the helper cannot be used, manually download and verify both hashes before extraction, then use the canonical Python pipeline.
3. Verify the rootfs image SHA-256 above.
4. Run `testenv/scripts/verify-pw6-rootfs.py <ROOTFS> --rootfs-image <IMAGE>` from the recorded current branch head where applicable.
5. Make the **extracted rootfs private bytes** available to the VM through a private/mounted path or approved private artifact. Do not commit firmware/rootfs bytes into GitHub source.
6. Commit only a sanitized verification report containing source commit, tool versions, exact commands, firmware SHA-256/MD5, rootfs SHA-256, manifest hash and final `PW6 rootfs verification: PASS`.

Acceptance criteria:

```text
/lib/ld-linux-armhf.so.3 SHA256 = a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
/lib/libc.so.6             SHA256 = 5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
/usr/lib/libwebkitgtk-1.0.so.0.7.2
                              SHA256 = 6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max = 2.35
verify-pw6-rootfs.py = PASS
```

Output to VM/private channel:

```text
<PRIVATE_DIR>/pw6-5.19.6-rootfs/
<PRIVATE_DIR>/pw6-rootfs.img                    # if --keep-image was used
sanitized GitHub report with no proprietary bytes
```

No device serial, credentials, Wi-Fi state or user content may enter the report.

### Task C — independent package/lifecycle audit

Review `native/app.c` plus `app_part*.inc`, `native/audio.c`, `native/sync.c`, `scripts/launch.sh`, `scripts/sync.sh`, packaging and test scripts for repeated launch/raise/exit, stale PID validation, clean shutdown, Bluetooth reroute, credentials/state exclusion and absence of historical runtime dependencies.

The current source intentionally uses `${KAP_OPERATION_LOCK_DIR:-$APP/.kap-operation.lock}` for launch/sync mutual exclusion. Audit this mechanism specifically for:

- TOCTOU gaps before child PID publication;
- stale/dead/zombie owner reclamation;
- live sync owner refusal behavior;
- launcher-triggered sync followed by relaunch;
- signal/error cleanup of lock ownership;
- exclusion of transient lock files from release archives.

Acceptance: report exact source commit and either PASS or file/line-specific defects. Do not mark the project complete.

### Task D — hardware-in-the-loop bridge

Do not begin until `HANDOFF.md` records a **final GitHub-persisted** installation-package SHA-256 and test-bundle SHA-256.

Then verify checksums, back up `/mnt/us/anki_data`, install package/test agent, run automated USBNetwork/SSH tests, ask the user only for irreducibly physical actions, sanitize logs and write the HIL report.

## Hardware report format

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

Do not include AnkiWeb keys, collection/media contents, device serials, Wi-Fi data or unsanitized logs.

## Worker log

Use:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex task is currently claimed.

## Current assignment

No local-host compilation action is requested. Task B may be claimed by a networked Codex/local worker solely to transport the exact verified rootfs private input. All actual build/QEMU/package work remains VM-owned.

## Completion rule

A worker must not mark the port complete. Completion is recorded only in `HANDOFF.md` after a reproducible build from current canonical ordinary source, full tests, ARMHF ABI audit, exact-rootfs QEMU smoke, package audit, durable final GitHub artifact persistence and real-device acceptance. Hardware acceptance must never be inferred from VM or CI results.
