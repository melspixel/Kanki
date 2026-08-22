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
docs/VM_GIT_IDENTITY_FAIL_CLOSED_20260822.md
docs/logs/KAP_GIT_IDENTITY_TARGETED_20260822.log
docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md
docs/logs/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log
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

The old installer remains stale and must never be relabeled final:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Exact PW6 5.19.6 runtime identity

Canonical manifest: `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`.

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

## Release-provenance hardening

### Rootfs/QEMU binding

`ROOTFS_IMAGE` is mandatory and must match the canonical full-image SHA-256. `run-qemu-smoke.sh` verifies the supplied extracted tree and retained image, invalidates old dynamic PASS evidence, requires `debugfs`, freshly `rdump`s the verified image to a private temporary tree, verifies that tree, and runs every QEMU `-L` check only against the image-derived runtime. Provenance records `rootfs_input_verified=true`, `rootfs_verified=true`, and `rootfs_runtime_source=verified-image-rdump`. `package-and-audit.sh` rejects all older image-hash-only/caller-tree QEMU evidence.

Previous targeted regression: 9/9 PASS; `docs/logs/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log` SHA-256 `985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac`.

### Git object/source identity — newest hardening

A deeper audit found that the source identity checks were still not completely fail-closed. Plain `git rev-parse HEAD` can print a ref value even when the referenced commit object cannot be resolved; then `git status` fails. A failed `git status` nested inside `[ -n "$(...)" ]` can be interpreted as an empty clean result under Bash `set -e` contexts. Packaging had a stronger gap: its Git checkout check was optional, so a copied non-Git project tree could theoretically package modified maintained `web/`, `scripts/`, config or document launcher bytes while declaring an arbitrary syntactically valid `BUILD_COMMIT`.

This is now closed:

```text
run-host-backend-gates.sh
run-armhf-gates.sh
run-qemu-smoke.sh
  -> require git rev-parse --verify 'HEAD^{commit}'
  -> explicitly require git status itself to succeed
  -> reject dirty source
  -> host/ARMHF also require pinned Anki HEAD^{commit} to resolve

package-and-audit.sh
  -> now requires a real resolvable Git project checkout unconditionally
  -> requires HEAD == BUILD_COMMIT
  -> explicitly fails if source-tree cleanliness cannot be established
  -> therefore cannot create final ZIP bytes from a copied/non-Git or broken-object source tree
```

Current production/test blobs:

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

Targeted Git failure-mode reproducer:

```text
clean resolvable commit: PASS
dirty tree detection: PASS
plain rev-parse with missing HEAD object reproduced old unsafe prerequisite
old status-command-substitution failure reproduced as survivable
HEAD^{commit} missing-object rejection: PASS
non-Git package-source rejection: PASS
log SHA-256 649526115118aa93996b3e66f75fff77111e0d0abee506bff167cb6cc0da13d7
```

Exact defect model, commands, commits and evidence are in `docs/VM_GIT_IDENTITY_FAIL_CLOSED_20260822.md`.

Lifecycle hardening also rejects stale zombie operation-lock owners and protects wrapper-death/sync collection ownership; see the earlier `docs/VM_*_20260822.md` reports.

## Current environment limitation

No fresh **complete current-head** build is claimed. Normal network access in the execution container still fails DNS resolution, including both GitHub and the official Amazon S3 firmware host:

```text
git clone ... https://github.com/melspixel/Kanki.git
fatal: Could not resolve host: github.com
rc=128

curl ... https://s3.amazonaws.com/firmwaredownloads/...
curl: (6) Could not resolve host: s3.amazonaws.com
```

The latest observed GitHub Actions checkpoint for the code-hardening head also failed before any recorded workflow step (run `32539353539`, job `96946124261`; steps list empty), so it is infrastructure evidence, not a test result.

The private checksum-matching PW6 rootfs tree **and retained image** are absent. Historical/synthetic evidence must not be promoted to final provenance.

## Local/Codex boundary

`CODEX_COORDINATION.md` Task B remains the only useful pre-release local task: transport the checksum-verified private PW6 rootfs tree **plus retained `pw6-rootfs.img`** into the VM/private channel. It must use `--keep-image`, verify the full image SHA-256 above, and persist only a sanitized verification report. Compilation, image-derived QEMU execution and packaging remain VM-owned.

## Ordered next actions

1. Materialize the then-current clean branch head in a network-capable build VM with complete Git objects, exact pinned Anki, Cargo cache, protoc and KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` in addition to the existing build/QEMU toolchain.
3. Run complete static gates, including the new missing-Git-object/non-Git-package regressions plus image-derived QEMU/package provenance tests.
4. From the same source/Anki identity, run full official backend tests and all five real APKG integrations including typed-answer coverage.
5. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit.
6. Supply both private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
7. Run exact-rootfs QEMU against a temporary runtime tree freshly `rdump`ed from that exact image and persist new provenance/evidence.
8. Only then run package audit/reproducibility/privacy/content checks and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
9. Begin separate physical PW6 HIL only after software-delivery hashes exist.

## Release record

**Not released.**
