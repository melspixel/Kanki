# Kindle Anki Port — Codex Coordination Channel

Last updated: 2026-08-22 UTC

## Purpose and boundary

This file is the only coordination surface for work that genuinely requires a local/Codex worker. Before taking work, read `HANDOFF.md`, `PROGRESS.md`, `docs/TEST_ENVIRONMENT.md`, and `VM_RUNBOOK.md`.

The user's local host is **not** an ordinary compiler requirement. All normal source edits, Anki/Rust work, host tests, real-APKG tests, ARMHF compilation, ABI/GLIBC audits, QEMU execution, packaging and GitHub persistence remain VM-owned. A local/Codex worker may only transport a private target input the VM cannot obtain directly or bridge a physical PW6 for HIL after software release.

Do not import Ranki, `rewrite-v1`, preload runtimes, historical template patches, a local scheduler/renderer reimplementation, or any other old implementation dependency.

## Current release chain

```text
clean current source
-> official Anki 26.08.1 backend/semantic tests
-> five real APKG integrations including typed-answer coverage
-> ARMHF + ELF/ABI/GLIBC/export audit
-> L2 exact PW6 5.19.6 QEMU using BOTH:
     checksum-verified extracted rootfs
     retained rootfs image with canonical full-image SHA-256
-> QEMU-bound package/privacy/reproducibility audit
-> final ZIP/SHA-256/manifest/contents/reports persisted on GitHub
-> separate physical PW6 HIL result
```

A directory that merely contains the pinned loader/libc/WebKit files is no longer sufficient L2 identity. `run-qemu-smoke.sh` now requires `ROOTFS_IMAGE`, the rootfs verifier checks that image against the canonical `rootfs_image.sha256`, QEMU provenance records the image hash without the private path, and `package-and-audit.sh` revalidates that exact hash before packaging.

The historical ZIP SHA-256

```text
9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

remains stale and must not be published as final.

## Canonical pins

```text
official Anki commit    e5a6fbe27fdd4d57d5f712191b4a753032e57853
Anki release            26.08.1
Rust target             armv7-unknown-linux-gnueabihf
Kindle GCC triple       arm-kindlehf-linux-gnueabihf
koxtoolchain            2025.05
PW6 firmware            5.19.6 / 4832160042
firmware MD5            697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256        72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256    b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

Full runtime-file hashes are committed in `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`.

## Current environment status

The ordinary independent source tree is in GitHub. Historical checkpoints include `539 passed; 0 failed` for official Anki `rslib`, five real APKG C-ABI integrations, ARMHF hard-float/ABI evidence and deterministic reviewer/sync/lifecycle tests, but all release-critical gates must be rerun from the eventual final clean head.

The current execution container has been unable to resolve `github.com` through normal Git DNS. Public GitHub Actions also currently fail before any recorded step. The private PW6 rootfs tree/image pair is not mounted. None of those conditions authorizes moving ordinary compilation onto the user's host or weakening L2.

## Tasks a local/Codex worker may take

A worker must append a dated claim under **Worker log** before performing a task.

### Task A — independent ordinary-source verification

Input:

```text
current melspixel/Kanki:kindle-anki-port
kindle-anki-port/
.github/workflows/kindle-anki-port.yml
```

Task: verify every maintained build/package input resolves from ordinary source plus explicitly pinned upstream/toolchain inputs; verify no archive parts, overlay, Ranki or hidden historical source is required; verify public CI cannot emit a final installer without private exact-rootfs evidence.

Output: sanitized source-commit-pinned report with exact commands, inspected paths, PASS/defects.

Acceptance: no hidden implementation dependency and no package-before-exact-QEMU bypass.

### Task B — exact PW6 5.19.6 private rootfs inputs

This task **does not compile the project**. It exists only to transport the private runtime bytes the VM lacks.

Required input source: only the official Amazon alias/direct object recorded in the canonical manifest. Do not substitute community mirrors.

Required procedure:

```sh
# 1. Record current project commit.
git rev-parse HEAD

# 2. Prepare from the official firmware source and RETAIN the image.
testenv/scripts/prepare-pw6-rootfs.sh \
  --download \
  --firmware <PRIVATE_DIR>/update_kindle_all_new_paperwhite_12th_5.19.6.bin \
  --output <PRIVATE_DIR>/pw6-5.19.6-rootfs \
  --keep-image

# 3. Verify the extracted tree AND retained full image.
python3 testenv/scripts/verify-pw6-rootfs.py \
  <PRIVATE_DIR>/pw6-5.19.6-rootfs \
  --rootfs-image <PRIVATE_DIR>/pw6-rootfs.img
```

The helper must verify both pinned firmware MD5 and SHA-256 before extraction. The retained `pw6-rootfs.img` is **mandatory** for release L2 and must hash exactly to:

```text
b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

Acceptance also requires:

```text
/lib/ld-linux-armhf.so.3
  a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
/lib/libc.so.6
  5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
/usr/lib/libwebkitgtk-1.0.so.0.7.2
  6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max = 2.35
rootfs image sha256: PASS b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
PW6 rootfs verification: PASS
```

Required private-channel output:

```text
<PRIVATE_DIR>/pw6-5.19.6-rootfs/
<PRIVATE_DIR>/pw6-rootfs.img
```

Required GitHub output: only a sanitized report containing project commit, tool versions, exact commands, firmware MD5/SHA-256, rootfs-image SHA-256, canonical manifest SHA-256 and verifier result. Never commit firmware, image, extracted proprietary libraries, private paths, device identifiers, credentials, Wi-Fi state or user content.

After Task B succeeds, the **VM** must run fresh ARMHF, exact-rootfs QEMU with both `ROOTFS` and `ROOTFS_IMAGE`, and the package gate.

### Task C — independent package/lifecycle audit

Input:

```text
native/app.c
native/audio.c
native/sync.c
scripts/launch.sh
scripts/sync.sh
packaging/
testenv/scripts/run-qemu-smoke.sh
testenv/scripts/package-and-audit.sh
testenv/scripts/vm-advance.py
Makefile
testenv/Makefile
relevant tests/docs
```

Audit: launcher/operation-lock races, collection ownership, interrupted audio/sync cleanup, package privacy, source/Anki/manifest/rootfs-image/ARMHF QEMU binding, private-path leakage, and every possible package-before-QEMU bypass.

Output: source-commit-pinned sanitized report with exact defects or PASS.

Acceptance: no release path can treat an unbound extracted rootfs directory as exact L2 evidence; no final package can bypass fresh exact-rootfs-image QEMU.

### Task D — physical PW6 HIL bridge

Do not begin until `HANDOFF.md` records a final GitHub-persisted software-release installer SHA-256 and report hashes.

Input: final installer/checksums, physical jailbroken PW6, HIL scripts.

Task: verify hashes, back up `/mnt/us/anki_data`, install, automate USBNetwork/SSH checks where possible, collect sanitized logs/screenshots, and ask the user only for irreducibly physical observations such as audible output, touch/IME, Bluetooth pairing and power/suspend behavior.

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

Never include AnkiWeb keys, collection/media contents, device serials, Wi-Fi data or unsanitized logs. HIL is separate from software delivery and cannot be inferred from VM/QEMU.

## Worker log

Format:

```text
YYYY-MM-DD HH:MM UTC | worker | task | status | commit/report
```

No Codex/local task is currently claimed.

## Completion semantics

A local/Codex worker must never mark the project complete itself. Software delivery is recorded only after the current clean source, full host/backend/APKG tests, ARMHF/ABI/GLIBC, retained-image-bound exact-rootfs QEMU, package audit, final ZIP/SHA-256/manifest/contents and complete reports are all durably persisted on GitHub. Physical PW6 acceptance is a separate later result.
