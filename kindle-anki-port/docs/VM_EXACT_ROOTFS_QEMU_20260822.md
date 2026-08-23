# VM exact PW6 rootfs and QEMU checkpoint — 2026-08-22

## Scope

This checkpoint closes the previously external exact-runtime input gate for the independent `kindle-anki-port` branch. The firmware/rootfs bytes were used only as private VM test inputs and were not committed.

## Pinned inputs

- Device/platform: PW6 / Bellatrix4 / Paperwhite 12th generation
- Firmware: 5.19.6, OTA code `4832160042`
- Firmware file: `update_kindle_all_new_paperwhite_12th_5.19.6.bin`
- Firmware SHA-256: `72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c`
- Rootfs image SHA-256: `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`
- Cross target: `armv7-unknown-linux-gnueabihf`
- Kindle GCC triple: `arm-kindlehf-linux-gnueabihf`

## Procedure

1. Downloaded the exact Amazon firmware object.
2. Verified the complete firmware SHA-256 before extraction.
3. Built KindleTool from its upstream source and extracted the update package.
4. Required exactly one rootfs image and verified its complete SHA-256.
5. Extracted the filesystem without privileged mounting using `debugfs rdump`.
6. Ran `testenv/scripts/verify-pw6-rootfs.py` against the extracted tree and source image.
7. Rebuilt the current native workers with the Kindle hard-float compiler and paired them with the previously built semantic Anki backend.
8. Ran `testenv/scripts/run-qemu-smoke.sh` with the exact rootfs, current ARMHF artifacts and QEMU user mode.

## Result

All steps above returned success. The verifier accepted the pinned runtime files, firmware identity and target GLIBC ceiling. The exact-rootfs QEMU smoke returned zero and exercised the target dynamic loader/runtime path rather than the cross-toolchain sysroot.

This result supersedes the earlier state where only a static ARM sanity binary had run and exact rootfs bytes were unavailable.

## Security and repository policy

The firmware, rootfs image, extracted rootfs and Amazon proprietary libraries are not committed or packaged. GitHub retains only hashes, test scripts and this derived result. The final installer remains subject to a fresh canonical-head build, manifest/privacy audit and hardware-in-the-loop acceptance.
