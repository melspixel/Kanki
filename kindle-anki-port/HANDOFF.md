# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical continuation point

- Repository: `melspixel/Kanki`
- Branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Official Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Always resolve the live branch HEAD before building; documentation/test-evidence commits advance HEAD too.

Read before continuing:

```text
HANDOFF.md
PROGRESS.md
CODEX_COORDINATION.md
docs/TEST_ENVIRONMENT.md
VM_RUNBOOK.md
```

Newest detailed report/evidence:

```text
docs/VM_ROOTFS_IMAGE_PROVENANCE_HARDENING_20260822.md
docs/logs/KAP_ROOTFS_IMAGE_QEMU_TARGETED_20260822.log
docs/logs/KAP_ROOTFS_IMAGE_BINDING_20260822.log
docs/VM_RELEASE_GATE_POLICY_HARDENING_20260822.md
docs/VM_PACKAGE_QEMU_BINDING_20260822.md
docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md
```

## Product boundary

This is an independent Kindle port of desktop Anki, not a Ranki/rewrite patch set. Official Anki `rslib` owns collection, scheduler, renderer semantics, typed answers, media, sync and undo. Kindle code owns platform integration only. Production contains no Ranki, `rewrite-v1`, `LD_PRELOAD`, deck-name routing or note-type-specific CSS patches.

The user's local host is not an ordinary compiler requirement. Physical PW6 acceptance is a separate final result and can never be inferred from VM/QEMU.

## Completion rule

Do **not** mark software delivered until one coherent current-head provenance chain is green and durably persisted:

```text
complete ordinary source
-> complete static gates
-> official Anki 26.08.1 backend tests
-> five real APKG integrations including typed-answer coverage
-> ARMv7 hard-float build + ELF/ABI/GLIBC/export audit
-> exact PW6 5.19.6 L2 using BOTH:
     checksum-verified extracted rootfs
     retained rootfs image matching the canonical full-image SHA-256
-> QEMU-bound package/privacy/reproducibility audit
-> final ZIP + SHA-256 + internal manifest + contents + complete reports on GitHub
```

Only after those software artifacts/hashes exist may physical PW6 HIL begin; HIL is recorded separately.

## Historical green checkpoints — regression evidence only

```text
official Anki rslib: 539 passed; 0 failed
five real APKG C-ABI reviewer integrations: PASS
reviewer runtime fixture groups: 10 PASS
test_sync_worker: PASS
ARMHF checkpoint:
  kap-app           ARM EABI5 hard-float, GLIBC_2.4
  kap-audio         ARM EABI5 hard-float, GLIBC_2.4
  kap-sync          ARM EABI5 hard-float, GLIBC_2.4
  libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc oracle ceiling: GLIBC_2.35
```

These predate current release-provenance hardening and must be rerun from the eventual release head.

The old installer remains stale:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

Never publish or relabel it as final.

## Exact PW6 5.19.6 runtime identity

Canonical manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned values:

```text
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max          2.35
```

The actual checksum-matching private rootfs tree/image pair is not currently mounted in the execution VM. Hash metadata alone is never accepted as a dynamic L2 run.

## Current release-provenance hardening

### Source/ARMHF/QEMU/package identity

Existing production gates already require:

```text
clean project HEAD == BUILD_COMMIT
pinned Anki HEAD == upstream.lock.json
ARMHF-GATES.txt == PASS
ARMHF source/Anki provenance matches package identity
QEMU source/Anki/manifest/binary hashes match the exact release inputs
package construction occurs only after QEMU PASS
```

Lifecycle hardening also rejects stale zombie operation-lock owners and protects wrapper-death/sync collection ownership. See the earlier `docs/VM_*_20260822.md` reports for exact regressions.

### New full rootfs-image identity requirement

A new audit found that `run-qemu-smoke.sh` previously made `ROOTFS_IMAGE` optional. The verifier would then check only selected loader/libc/WebKit hashes and version markers in an extracted directory, so L2 could not prove the complete root filesystem matched the canonical image.

This is fixed fail-closed:

```text
run-qemu-smoke.sh
  -> ROOTFS_IMAGE is mandatory and must be a regular file
  -> verify-pw6-rootfs.py always receives --rootfs-image
  -> QEMU-PROVENANCE.txt always records rootfs_image_sha256
  -> no private rootfs/image path is persisted

package-and-audit.sh
  -> requires rootfs_verified=true
  -> requires QEMU rootfs_image_sha256 == canonical manifest rootfs_image.sha256
  -> requires rootfs-verification.txt to contain the canonical image PASS marker
  -> records rootfs_image_sha256 in PACKAGE-PROVENANCE.txt

Makefile / testenv Makefile / vm-advance.py
  -> require/propagate the retained image for exact-rootfs L2
  -> vm-advance --rootfs now requires --rootfs-image
```

Current core/test blobs:

```text
testenv/scripts/run-qemu-smoke.sh       21daca49e9908f2855754f133a9d221d29916d7f
testenv/scripts/package-and-audit.sh    0bd1f398e2165ee7da73318816466c4de2a1f282
testenv/scripts/vm-advance.py           bdae4cc700eb390d1cf62eee33c29228caa68c80
Makefile                                f909aeb9152ffd36beaba5246034b128bc074895
testenv/Makefile                        8988b75883754700383665eb1b5dc9c49666e6e0
tests/test_qemu_provenance.py           bc807b3adadae8b0b18b537818808c62f8fc1d31
tests/test_package_reproducibility.py   8d2dc69a6cf2673aa6cd6454bca2b6252e23cd79
tests/test_build_entrypoints.py         9ec13f75c8950a8c9bbd82cb41ae70f33f0e997f
tests/test_vm_advance_contract.py       f9b86756cd029208393ef5028a1766ec609be6f5
```

Targeted validation performed in the current execution container:

```text
rootfs-image QEMU fixture: 4/4 PASS
  valid image                         PASS
  missing image                       rc=66
  non-file image                      rc=66
  stale ARMHF source provenance       rc=66
log SHA-256 ca9a95f5bacea22d190c507098d697f565d1e44a88dc5dfba556699f8e1782c3

package image-binding predicate:
  matching image                      rc=0
  wrong image hash                    rc=66
  rootfs_verified=false               rc=66
  missing canonical image PASS marker rc=66
log SHA-256 8f38bd14c63e79de30b01d4d0122010680e276d2cc62f08a83e9c1289b540d5e
```

These are targeted regressions, not a complete current-head build. Detailed commands and commits are in `docs/VM_ROOTFS_IMAGE_PROVENANCE_HARDENING_20260822.md`.

## Current environment limitation

No fresh **complete current-head** build is claimed. Normal Git materialization still fails in the execution container:

```text
git clone ... https://github.com/melspixel/Kanki.git
fatal: Could not resolve host: github.com
rc=128
```

The canonical GitHub Actions run at checkpoint `5fbb1b977bd1c15c72039eb299ec3221008c4fab` was run `32534150567`; build job `96931794076` again failed before any recorded step. This unavailable-runner/pre-step symptom is not counted as code validation.

The private checksum-matching PW6 rootfs tree **and retained image** are also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Local/Codex boundary

`CODEX_COORDINATION.md` Task B is the only useful pre-release local task: transport the checksum-verified private PW6 rootfs tree **plus retained `pw6-rootfs.img`** into the VM/private channel. It must use `--keep-image`, verify the full image SHA-256 above, and persist only a sanitized verification report. Compilation, QEMU execution and packaging remain VM-owned.

## Ordered next actions

1. Materialize the then-current clean branch head in a network-capable build VM with exact pinned Anki, Cargo cache, protoc and KindleHF inputs.
2. Run complete static gates, including updated rootfs-image QEMU/package/entrypoint/VM-driver tests.
3. From the same source/Anki identity, run full official backend tests and all five real APKG integrations including typed-answer coverage.
4. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit.
5. Supply both private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
6. Run exact-rootfs QEMU against those exact fresh ARMHF outputs and persist full-image-bound QEMU evidence.
7. Only then run package audit/reproducibility/privacy/content checks and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
8. Begin separate physical PW6 HIL only after software-delivery hashes exist.

## Release record

**Not released.**
