# Kindle Anki Port test environment

This directory turns the port into a reproducible sequence of release gates rather than a device-only experiment.

## Gate order

1. `make test` / `scripts/run-static-gates.sh` — Python/JavaScript/Shell contracts, lifecycle regressions, provenance fixtures and strict host C compile.
2. `scripts/run-host-backend-gates.sh` — use the exact pinned Anki checkout, run the official backend/semantic tests and produce the host release backend.
3. Five-real-APKG integration — exercise the C ABI reviewer lifecycle, including the required typed-answer fixture.
4. `scripts/run-armhf-gates.sh` — cross-build the Rust backend and native workers with KindleHF and persist ARMHF/ABI/GLIBC/export provenance.
5. `scripts/run-qemu-smoke.sh` — require both the checksum-verified PW6 5.19.6 extracted rootfs and the retained rootfs image. Verify the supplied tree, verify the full canonical image SHA-256, freshly `debugfs rdump` that verified image into a private temporary runtime tree, verify the derived tree, and run all QEMU `-L` checks only against that image-derived tree. Persist both rootfs verification reports plus QEMU/runtime provenance.
6. `scripts/package-and-audit.sh` — **only after step 5 passes**, assemble the installer, verify the internal manifest, revalidate the rootfs-image/QEMU evidence, require `rootfs_runtime_source=verified-image-rdump`, verify tested binary hashes, and enforce privacy/reproducibility/package policy.
7. Persist the final ZIP, external SHA-256, contents and complete ARMHF/QEMU/package/test reports durably on GitHub.
8. PW6 hardware-in-the-loop acceptance — separate final gate; never inferred from QEMU.

A missing private PW6 rootfs tree **or retained checksum-matching rootfs image** is a release blocker, not permission to skip step 5. Without both inputs, stop at an ARMHF checkpoint and do not create a final-looking `Kindle-Anki-Port-PW6-armhf.zip`.

Public GitHub Actions do not have the private PW6 rootfs tree/image. The canonical workflow therefore emits an explicit `NOT-A-RELEASE.txt` host/ARMHF checkpoint and intentionally does not invoke the production package path.

The scripts do not silently substitute unpinned inputs. Paths to the Anki checkout, offline Cargo cache, pinned `protoc`, KindleHF toolchain, private extracted rootfs and retained verified rootfs image are supplied explicitly where required. `run-qemu-smoke.sh` rejects an extracted directory without `ROOTFS_IMAGE`, verifies both inputs, requires `debugfs`, invalidates prior dynamic PASS/provenance before a fresh attempt, and uses a temporary tree re-extracted from the verified image as the actual QEMU runtime. Production packaging additionally requires `QEMU=<fresh run-qemu-smoke output>` and fails closed if that evidence belongs to different source/Anki/manifest/rootfs-image/ARMHF bytes or lacks the image-derived-runtime marker.
