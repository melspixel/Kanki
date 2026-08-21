# Kindle Anki Port test environment

This directory turns the port into a reproducible sequence of release gates rather than a device-only experiment.

## Gate order

1. `make test` / `scripts/run-static-gates.sh` — Python/JavaScript/Shell contracts, lifecycle regressions, provenance fixtures and strict host C compile.
2. `scripts/run-host-backend-gates.sh` — use the exact pinned Anki checkout, run the official backend/semantic tests and produce the host release backend.
3. Five-real-APKG integration — exercise the C ABI reviewer lifecycle, including the required typed-answer fixture.
4. `scripts/run-armhf-gates.sh` — cross-build the Rust backend and native workers with KindleHF and persist ARMHF/ABI/GLIBC/export provenance.
5. `scripts/run-qemu-smoke.sh` — load those exact ARMHF bytes against the checksum-verified PW6 5.19.6 rootfs under QEMU user mode and persist QEMU/rootfs provenance.
6. `scripts/package-and-audit.sh` — **only after step 5 passes**, assemble the installer, verify the internal manifest, revalidate the QEMU-tested binary hashes, and enforce privacy/reproducibility/package policy.
7. Persist the final ZIP, external SHA-256, contents and complete ARMHF/QEMU/package/test reports durably on GitHub.
8. PW6 hardware-in-the-loop acceptance — separate final gate; never inferred from QEMU.

A missing private PW6 rootfs is a release blocker, not permission to skip step 5. Without the exact checksum-matching rootfs, stop at an ARMHF checkpoint and do not create a final-looking `Kindle-Anki-Port-PW6-armhf.zip`.

Public GitHub Actions do not have the private PW6 rootfs. The canonical workflow therefore emits an explicit `NOT-A-RELEASE.txt` host/ARMHF checkpoint and intentionally does not invoke the production package path.

The scripts do not silently substitute unpinned inputs. Paths to the Anki checkout, offline Cargo cache, pinned `protoc`, KindleHF toolchain, and private verified rootfs are supplied explicitly where required. Production packaging additionally requires `QEMU=<fresh run-qemu-smoke output>` and fails closed if that evidence belongs to different source/Anki/manifest/ARMHF bytes.
