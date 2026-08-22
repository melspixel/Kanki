# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki semantic backend; no Ranki/rewrite/preload runtime |
| Ordinary GitHub source | complete | maintained source under `kindle-anki-port/` |
| Official Anki semantic bridge | green historical checkpoint | prior full `rslib`: `539 passed; 0 failed`; final clean-head rerun required |
| Five real APKG integration | green historical checkpoint | C-ABI reviewer lifecycle passed; typed-answer/AV observed; final clean-head rerun required |
| Reviewer/native host | deterministic fixtures green historically | full current-head rerun pending |
| Sync/collection ownership | hardened | wrapper-death/zombie-owner races reproduced and fixed |
| Git source identity | hardened further | host/ARMHF/QEMU require resolvable `HEAD^{commit}` + successful clean-status query; packaging now requires a real Git checkout unconditionally |
| Host/ARMHF source provenance | hardened | clean current project commit + exact resolvable pinned Anki commit required before build |
| ARMHF/ABI/GLIBC | green historical checkpoint | ARM hard-float outputs under target GLIBC ceiling; final clean-head rerun required |
| PW6 rootfs identity/preparation | hardened + private input pending | firmware/runtime hashes pinned; L2 requires both extracted tree and retained full image |
| Exact-rootfs QEMU provenance | hardened further | QEMU executes only against a tree freshly `rdump`ed from verified retained image; stale rerun PASS invalidated |
| Package privacy/provenance | hardened further | package requires exact-rootfs QEMU evidence and resolvable clean Git source bytes |
| Release entrypoints/orchestrator | hardened | Makefiles/VM driver/public CI prevent package-before-exact-QEMU; `--rootfs` requires `--rootfs-image` |
| Public GitHub Actions | checkpoint-only / infrastructure unavailable | latest observed checkpoint failed before any recorded step; not test evidence |
| Final ZIP persistence | incomplete | old ZIP stale; fresh current-head installer absent |
| PW6 hardware acceptance | not started | separate physical final result after software-delivery hashes exist |

## Historical checkpoints — not final provenance

```text
official Anki rslib: 539 passed; 0 failed
five real APKG C-ABI reviewer integrations: PASS
reviewer runtime fixture groups: 10 PASS
test_sync_worker: PASS
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc ceiling: GLIBC_2.35
```

These must be rerun from the eventual final clean source/Anki identity.

## Exact PW6 runtime identity

```text
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
GLIBC ceiling             2.35
```

Canonical manifest: `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`. The actual checksum-matching private extracted rootfs and retained rootfs image are still absent from the current VM.

## Image-derived exact-rootfs runtime binding

The L2 chain is fail-closed:

```text
run-qemu-smoke.sh
  verifies supplied ROOTFS against the pinned runtime oracle
  verifies retained ROOTFS_IMAGE against the canonical image SHA-256
  invalidates prior QEMU PASS/provenance before new dynamic L2 work
  requires debugfs
  rdump's the verified image into a private temporary rootfs
  verifies that image-derived rootfs
  runs backend/audio/sync QEMU only with -L <image-derived-rootfs>
  records rootfs_input_verified=true
  records rootfs_verified=true
  records rootfs_runtime_source=verified-image-rdump

package-and-audit.sh
  requires both rootfs verification reports
  requires matching image-derived-runtime QEMU provenance
  rejects older caller-tree/image-hash-only evidence
```

Previous targeted QEMU fixture: 9/9 PASS. Log SHA-256 `985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac`. Detailed report: `docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md`.

## New Git identity fail-closed hardening

A release provenance audit found two related failure modes:

1. `git rev-parse HEAD` can print a ref value while the referenced commit object is missing. A subsequent failed `git status` embedded in `[ -n "$(...)" ]` can survive Bash `set -e` and be mistaken for an empty clean result.
2. `package-and-audit.sh` treated the Git source check as optional, so a copied/non-Git project tree could in principle package changed maintained web/scripts/config/document bytes while declaring an arbitrary 40-hex `BUILD_COMMIT`.

Production gates now require:

```text
PROJECT HEAD^{commit} resolves
PROJECT HEAD == BUILD_COMMIT
PROJECT git status command itself succeeds
PROJECT tree is clean
host/ARMHF: pinned Anki HEAD^{commit} resolves and equals upstream.lock.json
package: Git checkout is mandatory, not optional
```

Current blobs:

```text
testenv/scripts/run-armhf-gates.sh          aeee9ba7f5759ce44b161c8669111f527a3dc0b2
testenv/scripts/run-host-backend-gates.sh   1efcdd18b017deed1b76871e1d598715eb298e56
testenv/scripts/run-qemu-smoke.sh           1bd183e72a1d6490eac36cb5a165c75074efd62a
testenv/scripts/package-and-audit.sh        9d41690315b8dcaa8333d2a6fe0cd2bc3b10f4b0
tests/test_armhf_provenance.py              9208c15a1ac243a413057abab5c550f0400a006c
tests/test_host_backend_provenance.py       9137193089492ba5834cd35613ceddae0a09e271
tests/test_qemu_provenance.py               6ff2672ac10772437f73e1cd35e8fa6b38867a87
tests/test_package_reproducibility.py       dfd005fa252f9f9211a6def7a2873439df77d527
```

The targeted local-Git reproducer covered clean/dirty behavior, reproduced the old missing-object + status-substitution fail-open precondition, verified `HEAD^{commit}` rejection, and verified non-Git package-source rejection. Result: all targeted cases PASS. Persisted log:

```text
docs/logs/KAP_GIT_IDENTITY_TARGETED_20260822.log
SHA-256 649526115118aa93996b3e66f75fff77111e0d0abee506bff167cb6cc0da13d7
```

Detailed report: `docs/VM_GIT_IDENTITY_FAIL_CLOSED_20260822.md`.

## Existing lifecycle/source/rootfs hardening

Previously persisted targeted evidence includes:

```text
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250

historical source-provenance fixture:
test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS

rootfs-image QEMU fixture         4/4 PASS
package rootfs-image predicates  matching image accepted; wrong image/rootfs_verified/missing marker rejected
```

The source-provenance suites now contain additional missing-Git-object regressions and require a complete static-gate rerun before release.

## Current validation limitation

No fresh complete current-head build is claimed. Ordinary network access in the execution container still fails DNS resolution:

```text
GitHub clone: Could not resolve host: github.com; rc=128
Amazon S3 firmware probe: Could not resolve host: s3.amazonaws.com; rc=6
```

The latest observed `Kindle Anki Port build checkpoint` workflow for code head `591536e2a18c913d62c5b715942bdf5f204b7229` was run `32539353539`; job `96946124261` completed failure with an empty recorded step list. That is an infrastructure failure, not a code/test result.

The private checksum-matching PW6 rootfs tree/image pair is also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Stale installer

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It remains stale and must not be published as final.

## Current blockers / next actions

1. Materialize the latest clean branch head with complete Git objects in a network-capable build VM with exact pinned Anki/Cargo/protoc/KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` plus existing host/QEMU/toolchain dependencies.
3. Run complete static gates, including the new missing-object/non-Git package regressions and current QEMU/package provenance suites.
4. Run full official Anki backend plus five real APKG integrations from that same source identity.
5. Run ARMHF cross-build and ABI/GLIBC/export audit.
6. Supply **both** private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` whose SHA-256 is `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
7. Run exact-rootfs QEMU; actual `-L` runtime must be the temporary tree freshly `rdump`ed from that exact verified image.
8. Run package/reproducibility/privacy/content gates and persist final ZIP/SHA-256/manifest/contents/all reports durably on GitHub.
9. Perform physical PW6 HIL separately after software-delivery hashes exist.

## Completion definition

**Not released.** Completion requires the full current-head source -> Anki -> APKG -> ARMHF -> retained-image-bound + image-derived-runtime exact-rootfs QEMU -> package -> durable GitHub evidence chain. Physical PW6 acceptance is a separate final result.
