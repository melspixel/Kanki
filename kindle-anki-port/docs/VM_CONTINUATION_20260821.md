# Kindle Anki Port — VM continuation evidence 2026-08-21

This report records the continuation after the first green VM checkpoint. It is additive to `VM_BUILD_20260821.md` and focuses on canonical source persistence, reproducibility hardening, exact PW6 runtime provenance, a fresh ARMHF/package rebuild, and the remaining exact-rootfs QEMU gate.

## Canonical repository progress

The independent port is now present as ordinary GitHub source files under `kindle-anki-port/`. Temporary split-source staging was retired in commit:

```text
0cf4716d8f66af96d38233ec5f723151787278d7
repo: retire archive staging after ordinary source materialization
```

Removed staging included root `part-00` … `part-08`, `restore.sh`, the old source-ZIP checksum, and `kindle-anki-port-overlay/overlay.part-*`. The ordinary source tree remains the build input.

The branch root README was also changed to point explicitly to the independent port and distinguish retained legacy Kanki/Ranki history from production inputs.

## Reproducibility / build-script hardening

The following source changes were persisted to GitHub:

- `4dde97b32a84254bf190b2184714efaa689ff177` — derive the ARMHF GLIBC compatibility ceiling from the KindleHF target sysroot instead of a hard-coded number;
- `e294aaa070153b19c9751d85ba025ee32f27cd0f` — select a safe protoc runtime library directory without injecting a bundled host `libc.so.6`;
- `5d850233c940db92fb35d0d0b38ddd7f177f519a` — make target-sysroot GLIBC derivation a source-contract gate;
- `3c0f59d6bc159c86d24748f87677499ed9515bb7` — rewrite the independent-port CI definition to build directly from ordinary source and execute the full host, ARMHF, QEMU-host-sanity and package gates;
- `edaea704f9c090c3d1e0eace1dc9e649d1623029` — exclude the legacy Ranki/Kanki workflow from pushes on `kindle-anki-port`.

The KindleHF toolchain sysroot advertises GLIBC symbol versions through 2.18. This is the conservative cross-build ceiling. It is distinct from the exact PW6 5.19.6 firmware runtime, whose extracted `libc.so.6` advertises symbols through GLIBC 2.35.

## Exact PW6 5.19.6 runtime pin

A target-runtime manifest is now committed at:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned inputs/evidence:

```text
firmware version:       5.19.6
version code:           4832160042
firmware SHA-256:       72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256:   b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256:         a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256:           5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256:      6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max:       2.35
```

The public firmware catalogue record also identifies version code `4832160042` as Kindle 5.19.6 and provides the official Amazon firmware-download URL/MD5. Proprietary firmware/rootfs bytes are not committed.

`testenv/scripts/verify-pw6-rootfs.py` was added to reject an unverified rootfs before QEMU execution. `run-qemu-smoke.sh` now calls this verifier before loading any ARM binary.

## Fresh ARMHF rebuild

A fresh VM rebuild was executed from VM source checkpoint:

```text
f1f5ff0a9edd37a14a5bd48213fcf1c21256a835
```

with:

```text
Anki:          e5a6fbe27fdd4d57d5f712191b4a753032e57853
Rust/Cargo:    1.92.0
Target:        armv7-unknown-linux-gnueabihf
Toolchain:     arm-kindlehf-linux-gnueabihf GCC 14.2.0
Sysroot GLIBC: 2.18
```

Result:

```text
ARMHF gates: PASS
```

Outputs:

```text
kap-app           ARM EABI5 hard-float; GLIBC_2.4
kap-audio         ARM EABI5 hard-float; GLIBC_2.4
kap-sync          ARM EABI5 hard-float; GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float; max GLIBC_2.18
```

The backend exported all required named `kap_*` symbols including collection/reviewer, sync, abort, health and build-info functions.

This fresh build remains VM-checkpoint evidence rather than the final release provenance because the final binary must be rebuilt/persisted from the current canonical GitHub source head after all non-hardware gates close.

## Fresh package checkpoint

The fresh ARMHF outputs were assembled and audited with `package-and-audit.sh`.

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256: 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

Passed:

- internal `MANIFEST.sha256` verification;
- package privacy/state policy;
- required-file policy;
- ZIP integrity;
- exclusion of collection/media DB, credentials, logs/PIDs and historical patch runtime dependencies.

The package contains 26 ZIP entries and includes `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so`, Web assets, launch/sync scripts, `BUILD.json`, manifest, Kindle document shortcuts and install documentation.

Again, this SHA-256 is a **checkpoint**, not the final release SHA-256.

## QEMU status

QEMU user-mode itself is available in the VM:

```text
qemu-arm 8.2.2
```

A statically linked ARMv7 hard-float sanity binary cross-built with the KindleHF compiler executes successfully:

```text
kap qemu armhf static sanity: ok
QEMU host sanity: PASS
```

Attempting to use the KindleHF *toolchain sysroot* as a stand-in dynamic runtime produced an `ld.so` relocation assertion even for a trivial dynamic ARM program. The toolchain sysroot is therefore correctly rejected as a target-runtime oracle.

The exact-rootfs dynamic QEMU gate remains pending because the current VM has the verified firmware/rootfs hashes and reports but not the complete extracted PW6 rootfs bytes. Package-network/DNS access in the current VM is restricted. This is an external test-input limitation, not a reason to move ordinary compilation to the user's local host.

## Remaining non-hardware work

1. Re-run host/ARMHF/package gates from a checkout/materialization matching the current canonical GitHub source head and record the resulting immutable source/build provenance.
2. Supply the checksum-verified PW6 5.19.6 rootfs privately to the VM, run `verify-pw6-rootfs.py`, then run backend/audio/sync QEMU smoke against that rootfs.
3. Expand deterministic renderer and sync decision/error fixtures.
4. Persist the final audited package, checksum, contents, ABI reports and test report durably on GitHub.
5. Only after these gates are green begin physical PW6 hardware acceptance.

## Integrity statement

Neither the fresh VM package nor the static-QEMU pass is sufficient to claim final release or hardware acceptance. Exact-rootfs QEMU and physical PW6 evidence remain separate gates.
