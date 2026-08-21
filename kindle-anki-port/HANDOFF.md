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
docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md
docs/logs/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log
docs/VM_ROOTFS_IMAGE_PROVENANCE_HARDENING_20260822.md
docs/logs/KAP_ROOTFS_IMAGE_QEMU_TARGETED_20260822.log
docs/logs/KAP_ROOTFS_IMAGE_BINDING_20260822.log
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
     QEMU runtime tree freshly rdump'ed from that verified retained image
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

### Full rootfs-image identity requirement

`ROOTFS_IMAGE` remains mandatory and must match the canonical full-image SHA-256. `run-qemu-smoke.sh` verifies both the supplied extracted tree and the retained image, and `package-and-audit.sh` revalidates the image hash and verification evidence.

### New image-derived runtime binding

A deeper audit found that the prior image requirement still executed QEMU with `-L "$ROOTFS"`, where `ROOTFS` was an independently supplied extracted directory. The verifier proves selected loader/libc/WebKit/version oracles plus the separately supplied image hash, but it cannot prove every library in that caller directory came from the retained image. The provenance could therefore name the canonical image while QEMU resolved other dependencies from unrelated bytes.

This is now fixed fail-closed:

```text
run-qemu-smoke.sh
  -> verifies supplied ROOTFS + canonical retained ROOTFS_IMAGE
  -> invalidates prior dynamic QEMU PASS/provenance before a new L2 attempt
  -> requires debugfs
  -> rdump's ROOTFS_IMAGE into a private temporary tree
  -> verifies that image-derived tree
  -> runs all QEMU -L checks only against the image-derived tree
  -> records rootfs_input_verified=true
  -> records rootfs_runtime_source=verified-image-rdump
  -> writes QEMU-SMOKE.txt only after all dynamic checks pass

package-and-audit.sh
  -> requires input-rootfs-verification.txt
  -> requires rootfs_input_verified=true
  -> requires rootfs_runtime_source=verified-image-rdump
  -> rejects all pre-hardening QEMU provenance
  -> persists both supplied-tree and image-derived verification reports
```

Current core/test blobs:

```text
testenv/scripts/run-qemu-smoke.sh       0a785125c0afa5957ae0c5115dd91ddd7ba896c9
testenv/scripts/package-and-audit.sh    524bbe1dc914b18eb146b5266a14794ddd0abe4f
tests/test_qemu_provenance.py           e1be1b7c5d4dc0a9bf747f8693ed4f2b3604b1a2
tests/test_package_reproducibility.py   d554df6aea2c90e80b379b366eb3f43664281bf9
```

Targeted QEMU provenance regression reconstructed in the current execution container:

```text
9 tests: PASS
  includes image-derived -L assertion
  includes failed-rerun stale PASS invalidation
log SHA-256 985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac
```

This is targeted regression evidence, not a complete current-head build. Exact commands and commits are in `docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md`.

## Current environment limitation

No fresh **complete current-head** build is claimed. Normal Git materialization still fails in the execution container:

```text
git clone ... https://github.com/melspixel/Kanki.git
fatal: Could not resolve host: github.com
rc=128
```

The private checksum-matching PW6 rootfs tree **and retained image** are also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Local/Codex boundary

`CODEX_COORDINATION.md` Task B remains the only useful pre-release local task: transport the checksum-verified private PW6 rootfs tree **plus retained `pw6-rootfs.img`** into the VM/private channel. It must use `--keep-image`, verify the full image SHA-256 above, and persist only a sanitized verification report. Compilation, image-derived QEMU execution and packaging remain VM-owned.

## Ordered next actions

1. Materialize the then-current clean branch head in a network-capable build VM with exact pinned Anki, Cargo cache, protoc and KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` in addition to the existing build/QEMU toolchain.
3. Run complete static gates, including updated image-derived QEMU/package provenance tests.
4. From the same source/Anki identity, run full official backend tests and all five real APKG integrations including typed-answer coverage.
5. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit.
6. Supply both private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
7. Run exact-rootfs QEMU against a temporary runtime tree rdump'ed from that exact image and persist the new provenance/evidence.
8. Only then run package audit/reproducibility/privacy/content checks and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
9. Begin separate physical PW6 HIL only after software-delivery hashes exist.

## Release record

**Not released.**
