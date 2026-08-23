# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22 UTC

## Current state

VM-side continuation remains active. Ordinary compilation is not delegated to
the user's host. GitHub Actions is retained only as a manual reproducibility
checkpoint because hosted-runner quota is exhausted.

Latest authoritative files:

```text
HANDOFF.md
PROGRESS.md
docs/VM_PLATFORM_REFERENCE_20260822.md
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
docs/REFERENCE_IMPLEMENTATIONS.md
```

## VM capabilities

Observed execution environment:

```text
OS             Debian 13 / x86-64
CPU            5 vCPU
RAM            about 5.9 GiB
free disk      about 38 GiB at inspection
privilege      root
available      git, GCC 14, Clang 17, CMake, Ninja, Node 22, Python, binutils, zip
missing        Rust/Cargo, protoc, qemu-arm, patchelf, debugfs, KindleHF
```

The resources are adequate for a controlled low-parallelism Anki/ARMHF build
once the pinned inputs are transported into the VM.

## Latest material advance

A reference-first Kindle platform checkpoint was implemented from starting head:

```text
ae349e0126bc95d4350acc6885e4ee443a91c88e
```

The new platform layer uses behavior observed in pinned Ranki,
KindlePuzzles/Gargoyle, em-dash and Kindle Explorer implementations, while
keeping Ranki and all other projects out of the production dependency graph.
Reference and license treatment is recorded in
`docs/REFERENCE_IMPLEMENTATIONS.md`.

Production additions:

```text
native/app_platform.inc
web/ime.js
tests/test_ime_runtime.js
tests/test_platform_adapter.c
tests/test_platform_reference_contract.py
```

Modified integration points:

```text
native/app.c
web/reviewer.html
testenv/scripts/run-static-gates.sh
.github/workflows/kindle-anki-port.yml
```

Behavior now covered:

- encoded Lab126/Awesome GTK application title;
- typed-answer focus opens `com.lab126.keyboard`;
- blur/reveal/back/close/non-question state closes it;
- first deck load clears a keyboard left by a crashed former process;
- duplicate focus events do not issue duplicate opens;
- direct `execl()` argument-vector invocation, no shell;
- bounded command child wait and reap;
- cleanup composition around the existing reviewer/audio lifecycle.

## Executed results

```text
node --check web/ime.js                                 PASS
node tests/test_ime_runtime.js                          PASS
gcc C99 -Wall -Wextra -Werror platform adapter test    PASS
maintained platform adapter executable test             PASS
startup close/open/duplicate/reveal-close argv audit    PASS
native app composition harness                          PASS
window-title preprocessing assertion                    PASS
Python reference/source/workflow contract               PASS
```

Observed `lipc-set-prop` argument sequence:

```text
-s com.lab126.keyboard close com.melspixel.kindleankiport
-s com.lab126.keyboard open  com.melspixel.kindleankiport:abc:1
-s com.lab126.keyboard close com.melspixel.kindleankiport
```

Combined log:

```text
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
SHA-256 42b0059bc09828ae077ab926cb9a23121dbcfff27720ffebf4767b67c413692a
```

This is targeted current-source evidence. It does not claim the complete
`run-static-gates.sh` invocation from a complete clean checkout.

## Existing evidence

Current-source targeted checkpoints also cover reviewer/CSS/audio-queue/native
host subsets and lifecycle/sync regressions. Historical broader checkpoints:

```text
official Anki rslib             539/539
five real APKG C-ABI flows      PASS
typed-answer and AV             observed in real APKG
ARMHF hard-float build          PASS
ABI/GLIBC audit                 PASS
QEMU static ARM sanity          PASS
```

Historical broad evidence must be rerun from the final clean source identity
because provenance gates were strengthened afterward.

## Active infrastructure blocker

Ordinary outbound networking is blocked in this VM. Independent attempts showed:

```text
normal DNS lookup               failed
git/curl to github.com          failed
direct-IP GitHub probes         failed
public DNS UDP probes           timed out
```

As a result, this VM cannot currently use `apt`, rustup, Cargo/crates.io or
ordinary Git clone/download to obtain missing inputs. This condition has been
reproduced enough to require user-visible notification; it is not being retried
silently without a changed transport method.

Recovery options, in priority order:

1. restore normal VM egress;
2. materialize a complete clean Git/source archive through an authenticated connector;
3. import a checksum-pinned offline bundle containing Rust 1.92.0, Cargo cache,
   protoc, QEMU/debugfs/patchelf and KindleHF 2025.05;
4. persist the bundle and checkpoints under Google Drive
   `GPT周转/Kindle-Anki-Port/`.

## Missing release inputs

```text
complete clean live Git checkout
exact official Anki checkout plus Fluent submodules
complete Cargo dependency cache
Rust 1.92.0 and armv7 target
protoc, qemu-user, debugfs, patchelf
KindleHF 2025.05
five real APKG private fixtures in the active VM
PW6 5.19.6 extracted rootfs
retained pw6-rootfs.img
```

The rootfs/image pair remains private and must not be committed.

## Next exact commands after materialization

From a complete clean project checkout and exact Anki checkout:

```sh
git rev-parse --verify 'HEAD^{commit}'
git status --porcelain

testenv/scripts/run-static-gates.sh

ANKI=<exact-anki> CARGO_HOME=<offline-cargo> PROTOC=<protoc> \
  testenv/scripts/run-host-backend-gates.sh

ANKI=<exact-anki> CARGO_HOME=<offline-cargo> PROTOC=<protoc> \
TOOLCHAIN_BIN=<kindlehf-bin> OUT=<armhf-out> BUILD_COMMIT=<project-head> \
  testenv/scripts/run-armhf-gates.sh
```

With both exact private target inputs:

```sh
python3 testenv/scripts/verify-pw6-rootfs.py \
  <rootfs> --rootfs-image <pw6-rootfs.img>

ROOTFS=<rootfs> ROOTFS_IMAGE=<pw6-rootfs.img> \
ARMHF=<armhf-out> OUT=<qemu-out> \
  testenv/scripts/run-qemu-smoke.sh

QEMU=<qemu-out> ARMHF=<armhf-out> OUT=<release-out> \
  testenv/scripts/package-and-audit.sh
```

Packaging before exact-rootfs QEMU remains prohibited.

## Persistence

Every material source change and its test contract is committed immediately to
`kindle-anki-port`. Logs/reports are committed and mirrored to the Google Drive
project workspace when transport is available. Firmware, rootfs, private APKGs,
collections, media and credentials are excluded.

## Release state

**Not released.** Physical PW6 testing has not started and cannot be inferred
from host/QEMU results.
