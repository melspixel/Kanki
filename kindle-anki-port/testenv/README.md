# Kindle Anki Port test environment

This directory turns the port into a reproducible series of gates rather than a device-only experiment.

## Gate order

1. `make test` — Python/JavaScript/Shell contracts and strict host C compile.
2. `scripts/run-host-backend-gates.sh` — inject into the exact Anki checkout, run `cargo check`, port tests, and a release build.
3. `scripts/run-armhf-gates.sh` — cross-build the Rust backend and native workers with KindleHF.
4. `scripts/package-and-audit.sh` — assemble the USB-root archive, verify the manifest, and enforce the privacy/package policy.
5. `scripts/run-qemu-smoke.sh` — load the ARMHF backend and worker self-tests against a checksum-verified PW6 rootfs under QEMU user mode.
6. PW6 hardware-in-the-loop acceptance.

The scripts do not download unpinned inputs. Paths to the Anki checkout, offline Cargo source/cache, Rust toolchain, `protoc`, and KindleHF toolchain are supplied explicitly.
