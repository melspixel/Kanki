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
| PW6 rootfs identity/preparation | hardened + private input pending | firmware/runtime hashes pinned; L2 requires both extracted tree and retained full image |
| Exact-rootfs QEMU provenance | hardened further | QEMU now executes only against a tree freshly rdump'ed from the verified retained image; stale rerun PASS is invalidated |
| Package privacy/provenance | hardened further | packaging requires matching exact-rootfs QEMU evidence including image-derived runtime provenance |
| Release entrypoints/orchestrator | hardened | Makefiles/VM driver/public CI prevent package-before-exact-QEMU; `--rootfs` requires `--rootfs-image` |
| Test-policy docs | hardened | L1 -> retained-image-bound/image-derived-runtime L2 QEMU -> L2.5 package -> durable software artifacts -> separate HIL |
| Public GitHub Actions | checkpoint-only / infrastructure unavailable | no final ZIP without private rootfs; recent jobs previously failed before recorded steps |
| Final ZIP persistence | incomplete | old ZIP stale; fresh current-head image-derived-runtime-bound installer absent |
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

## Image-derived exact-rootfs runtime binding

The earlier full-image requirement was necessary but not sufficient. The old L2 flow verified `ROOTFS_IMAGE`, then ran QEMU with `-L "$ROOTFS"` against a separately supplied extracted directory. Since the verifier only pins selected runtime files/version markers in that directory, other shared objects could theoretically differ while provenance still recorded the canonical full-image SHA-256.

The chain is now stronger and fail-closed:

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
  records rootfs_runtime_source=verified-image-rdump
  writes QEMU-SMOKE.txt only after all dynamic checks pass

package-and-audit.sh
  requires input-rootfs-verification.txt
  requires rootfs_input_verified=true
  requires rootfs_runtime_source=verified-image-rdump
  therefore rejects all older image-hash-only QEMU provenance
  persists both supplied-tree and image-derived verification evidence
```

Current implementation/test blobs:

```text
testenv/scripts/run-qemu-smoke.sh       0a785125c0afa5957ae0c5115dd91ddd7ba896c9
testenv/scripts/package-and-audit.sh    524bbe1dc914b18eb146b5266a14794ddd0abe4f
tests/test_qemu_provenance.py           e1be1b7c5d4dc0a9bf747f8693ed4f2b3604b1a2
tests/test_package_reproducibility.py   d554df6aea2c90e80b379b366eb3f43664281bf9
```

Targeted regression evidence from the current execution container:

```text
test_qemu_provenance.py-equivalent exact fixture: 9/9 PASS
includes:
  QEMU -L is not the caller-supplied ROOTFS
  QEMU -L points into kap-qemu-rootfs.* image-derived tree
  failed dynamic rerun removes old QEMU-SMOKE.txt
  failed dynamic rerun removes old QEMU-PROVENANCE.txt
  absent/non-file image rejected
  stale source / wrong Anki / non-PASS ARMHF / alternate manifest / dirty tree rejected

log SHA-256
  985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac
```

Detailed report: `docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md`.

## Existing lifecycle/source/rootfs hardening

Previously persisted targeted evidence includes:

```text
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250

test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS

rootfs-image QEMU fixture         4/4 PASS
package rootfs-image predicates  matching image accepted; wrong image/rootfs_verified/missing marker rejected
```

Release packaging was already bound to clean source identity, exact Anki pin, exact ARMHF binary hashes, canonical rootfs manifest and retained image hash. The newest work additionally binds the **runtime tree actually used by QEMU** to that image.

## Current validation limitation

No fresh complete current-head build is claimed. Ordinary Git materialization in the execution container still fails:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

The private checksum-matching PW6 rootfs tree/image pair is also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Stale installer

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It does not satisfy the current image-derived-runtime release chain and remains stale.

## Current blockers / next actions

1. Materialize the latest clean branch head in a network-capable build VM with exact pinned Anki/Cargo/protoc/KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` plus the existing host/QEMU/toolchain dependencies.
3. Run complete static gates, including the updated 9-case QEMU provenance suite and package reproducibility suite.
4. Run full official Anki backend plus five real APKG integrations from that same source identity.
5. Run ARMHF cross-build and ABI/GLIBC/export audit.
6. Supply **both** private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` whose SHA-256 is `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
7. Run exact-rootfs QEMU; actual `-L` runtime must be the temporary tree rdump'ed from that exact verified image and provenance must contain `rootfs_runtime_source=verified-image-rdump`.
8. Run package/reproducibility/privacy/content gates and persist final ZIP/SHA-256/manifest/contents/all reports durably on GitHub.
9. Perform physical PW6 HIL separately after software-delivery hashes exist.

## Completion definition

**Not released.** Completion requires the full current-head source -> Anki -> APKG -> ARMHF -> retained-image-bound + image-derived-runtime exact-rootfs QEMU -> package -> durable GitHub evidence chain. Physical PW6 acceptance is a separate final result.
