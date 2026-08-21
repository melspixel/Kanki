# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki semantic backend; no Ranki/rewrite/preload runtime |
| Ordinary GitHub source | complete | maintained source under `kindle-anki-port/` |
| Official Anki semantic bridge | green historical checkpoint | prior full `rslib`: `539 passed; 0 failed`; final clean-head rerun required |
| Five real APKG integration | green historical checkpoint | C-ABI reviewer lifecycle passed; typed-answer/AV observed; final clean-head rerun required |
| Reviewer/native host | deterministic fixtures green | host C/JS/runtime/lifecycle coverage persisted |
| Sync/collection ownership | hardened | wrapper-death/zombie-owner races reproduced and fixed |
| Host/ARMHF source provenance | hardened | clean project HEAD + exact pinned Anki HEAD enforced before build |
| ARMHF/ABI/GLIBC | green historical checkpoint | ARM hard-float outputs under target GLIBC ceiling; final clean-head rerun required |
| PW6 rootfs identity/preparation | hardened + private input pending | firmware/runtime hashes pinned; L2 now requires both extracted tree and retained full image |
| Exact-rootfs QEMU provenance | hardened | source/Anki/manifest/full-rootfs-image/ARMHF identity bound; private paths excluded |
| Package privacy/provenance | hardened | packaging requires matching exact-rootfs QEMU evidence, canonical image hash and exact tested ARMHF hashes |
| Release entrypoints/orchestrator | hardened | Makefiles/VM driver/public CI prevent package-before-exact-QEMU; `--rootfs` requires `--rootfs-image` |
| Test-policy docs | hardened | L1 -> retained-image-bound L2 QEMU -> L2.5 package -> durable software artifacts -> separate HIL |
| Public GitHub Actions | checkpoint-only / infrastructure unavailable | no final ZIP without private rootfs; current jobs fail before recorded steps |
| Final ZIP persistence | incomplete | old ZIP stale; fresh current-head image-bound installer absent |
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

Canonical manifest: `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`.

The actual checksum-matching private extracted rootfs and retained rootfs image are still absent from the current VM.

## Full rootfs-image release binding

A release audit found a concrete identity gap: `verify-pw6-rootfs.py` could verify the full image, but `run-qemu-smoke.sh` made `ROOTFS_IMAGE` optional. That allowed L2 to prove only selected pinned runtime files/version markers in an extracted directory rather than the full canonical filesystem image.

The chain is now fail-closed:

```text
run-qemu-smoke.sh
  requires ROOTFS_IMAGE regular file
  always invokes verify-pw6-rootfs.py --rootfs-image
  records rootfs_image_sha256, not the private path

package-and-audit.sh
  requires rootfs_verified=true
  requires QEMU rootfs_image_sha256 == manifest rootfs_image.sha256
  requires exact rootfs image PASS marker in rootfs-verification.txt
  records canonical rootfs_image_sha256 in PACKAGE-PROVENANCE.txt

Makefile / testenv Makefile
  require and propagate ROOTFS_IMAGE

vm-advance.py
  --rootfs requires --rootfs-image
  records only rootfs image SHA-256 in report inputs
  always propagates the image to L2
```

Current implementation/test blobs:

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

Policy surfaces were synchronized:

```text
docs/TEST_ENVIRONMENT.md   11016d272f34d248ad8919b521f133b6dd2e5088
testenv/README.md          372b305556cab6c09efe05a935c8203299c8c18d
docs/RELEASE_GATES.md      6ad2522d4f105edbf099febf585af8d96e0af086
VM_RUNBOOK.md              7bdb674f91157674c0cd2fb501662117d3c97651
CODEX_COORDINATION.md      85cae1a49ca21633c05fc37b32e328c6f259a0ba
```

Targeted regression evidence from the current execution container:

```text
rootfs-image QEMU fixture: 4/4 PASS
  valid retained image              PASS
  missing ROOTFS_IMAGE              rc=66
  non-file ROOTFS_IMAGE             rc=66
  stale ARMHF source provenance     rc=66
log SHA-256
  ca9a95f5bacea22d190c507098d697f565d1e44a88dc5dfba556699f8e1782c3

package rootfs-image predicates:
  correct image                     rc=0
  wrong image hash                  rc=66
  rootfs_verified=false             rc=66
  missing canonical image marker    rc=66
log SHA-256
  8f38bd14c63e79de30b01d4d0122010680e276d2cc62f08a83e9c1289b540d5e
```

Detailed report: `docs/VM_ROOTFS_IMAGE_PROVENANCE_HARDENING_20260822.md`.

## Existing lifecycle/source hardening

Previously persisted targeted evidence includes:

```text
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250

test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS
```

Release packaging is also already bound to clean source identity, exact Anki pin, exact ARMHF binary hashes and QEMU manifest/source/Anki evidence. The new work extends that invariant to the **full rootfs image** itself.

## Current validation limitation

No fresh complete current-head build is claimed. Ordinary Git materialization in the execution container still fails:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

Canonical GitHub Actions checkpoint run `32534150567` at checkpoint `5fbb1b977bd1c15c72039eb299ec3221008c4fab` also failed before any recorded job step; job `96931794076` exposed no steps. This is infrastructure/unavailable-runner evidence, not a code-level failure or green build.

## Stale installer

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It does not satisfy the current full-image-bound release chain and remains stale.

## Current blockers / next actions

1. Materialize the latest clean branch head in a network-capable build VM with exact pinned Anki/Cargo/protoc/KindleHF inputs.
2. Run complete static gates, including updated rootfs-image QEMU/package/entrypoint/VM-driver tests.
3. Run full official Anki backend plus five real APKG integrations from that same source identity.
4. Run ARMHF cross-build and ABI/GLIBC/export audit.
5. Supply **both** private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` whose SHA-256 is `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
6. Run exact-rootfs QEMU for those exact ARMHF bytes and persist full-image-bound QEMU evidence.
7. Run package/reproducibility/privacy/content gates and persist final ZIP/SHA-256/manifest/contents/all reports durably on GitHub.
8. Perform physical PW6 HIL separately after software-delivery hashes exist.

## Completion definition

**Not released.** Completion requires the full current-head source -> Anki -> APKG -> ARMHF -> retained-image-bound exact-rootfs QEMU -> package -> durable GitHub evidence chain. Physical PW6 acceptance is a separate final result.
