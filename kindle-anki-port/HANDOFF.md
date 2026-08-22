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
docs/VM_ANKI_OVERLAY_PROVENANCE_HARDENING_20260822.md
docs/logs/KAP_ANKI_OVERLAY_TARGETED_20260822.log
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

### Deterministic official-Anki overlay — newest hardening

A remaining source-provenance defect was found after the Git-identity work: proving that the Anki checkout `HEAD` equals the pinned 26.08.1 commit does **not** prove that Cargo compiles only those bytes. The host gate injected into an otherwise unconstrained Anki working tree, and the ARMHF gate trusted whatever working-tree overlay it inherited. Unrelated dirty Anki Rust/Cargo source could therefore theoretically participate in a build while provenance still named the correct official Anki commit.

This is now fail-closed. `tools/inject_into_anki.py` derives the expected overlay from pinned `HEAD` blobs plus clean project sources, verifies every overlay-owned byte, and requires the Git dirty-path set to equal exactly that deterministic overlay. It rejects unrelated tracked, staged, submodule-visible or untracked changes. It also resolves `HEAD^{commit}` itself.

Both release build paths enforce this independently:

```text
run-host-backend-gates.sh
  -> exact project/Anki identity checks
  -> deterministic injector + overlay verification
  -> force CARGO_TARGET_DIR=$ANKI/target
  -> delete target before official cargo check/test/build

run-armhf-gates.sh
  -> exact project/Anki identity checks
  -> rerun deterministic injector + overlay verification
  -> force CARGO_TARGET_DIR=$ANKI/target
  -> delete target before ARMHF cargo build
```

This also prevents a caller-supplied or copied ignored Cargo target directory from being reused as release evidence.

Current blobs:

```text
tools/inject_into_anki.py                     b7cf140e742c219ca0fe7acc675a08fe075e9c17
testenv/scripts/run-host-backend-gates.sh     3e2e463385713d096efab5a1f3c5ba5b065941ec
testenv/scripts/run-armhf-gates.sh            197054ebfd84b6b24d7f5237a79149f4ad7ccacb
tests/test_armhf_provenance.py                bc8fcfddde7657ad2df3646d541a9963ef887707
tests/test_injector.py                        9f8da713f59cf46ecfb42a49402426ff7a1ab858
```

Targeted local-Git reproducer: 7/7 PASS. It covered clean/idempotent injection, untracked/tracked/staged rejection, overlay-byte tamper rejection, and fresh gate-owned Cargo target recreation. Persisted log SHA-256:

```text
d3240f300e6b5605ead549f780d93907abfd8b38005d8536ad2d1c3db79040e8
```

Exact commands/defect model/commit chain: `docs/VM_ANKI_OVERLAY_PROVENANCE_HARDENING_20260822.md`.

### Rootfs/QEMU binding

`ROOTFS_IMAGE` is mandatory and must match the canonical full-image SHA-256. `run-qemu-smoke.sh` verifies the supplied extracted tree and retained image, invalidates old dynamic PASS evidence, requires `debugfs`, freshly `rdump`s the verified image to a private temporary tree, verifies that tree, and runs every QEMU `-L` check only against the image-derived runtime. Provenance records `rootfs_input_verified=true`, `rootfs_verified=true`, and `rootfs_runtime_source=verified-image-rdump`. `package-and-audit.sh` rejects all older image-hash-only/caller-tree QEMU evidence.

Previous targeted regression: 9/9 PASS; `docs/logs/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log` SHA-256 `985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac`.

### Git object/source identity

Host/ARMHF/QEMU require `git rev-parse --verify 'HEAD^{commit}'`, explicit successful source-status queries, matching `BUILD_COMMIT`, and clean maintained project source. Packaging requires a real resolvable clean Git project checkout unconditionally, so a copied/non-Git project tree or missing commit object cannot claim release provenance.

Targeted Git failure-mode reproducer log SHA-256: `649526115118aa93996b3e66f75fff77111e0d0abee506bff167cb6cc0da13d7`. Details: `docs/VM_GIT_IDENTITY_FAIL_CLOSED_20260822.md`.

Lifecycle hardening also rejects stale zombie operation-lock owners and protects wrapper-death/sync collection ownership; see the earlier `docs/VM_*_20260822.md` reports.

## Current environment limitation

No fresh **complete current-head** build is claimed. Normal network access in the execution container still fails DNS resolution. This run reconfirmed:

```text
git ls-remote https://github.com/melspixel/Kanki.git
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

The private checksum-matching PW6 rootfs tree **and retained image** are also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Local/Codex boundary

`CODEX_COORDINATION.md` Task B remains the only useful pre-release local task: transport the checksum-verified private PW6 rootfs tree **plus retained `pw6-rootfs.img`** into the VM/private channel. It must use `--keep-image`, verify the full image SHA-256 above, and persist only a sanitized verification report. Compilation, official Anki testing, ARMHF build, image-derived QEMU execution and packaging remain VM-owned.

## Ordered next actions

1. Resolve the live branch head, then materialize that exact clean commit in a network-capable build VM with complete Git objects, exact pinned Anki, Cargo cache, protoc and KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` in addition to the existing build/QEMU toolchain.
3. Run complete static gates, including deterministic Anki-overlay tests, missing-Git-object/non-Git package regressions and image-derived QEMU/package provenance tests.
4. From the same source/Anki identity, run the full official Anki backend gate. The hardened injector must report only the deterministic overlay, and Cargo target state must be freshly recreated.
5. Run all five real APKG integrations including typed-answer coverage against that fresh host library.
6. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit; the ARMHF gate independently re-verifies the exact Anki overlay and recreates Cargo target state.
7. Supply both private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
8. Run exact-rootfs QEMU against a temporary runtime tree freshly `rdump`ed from that exact image and persist new provenance/evidence.
9. Only then run package audit/reproducibility/privacy/content checks and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
10. Begin separate physical PW6 HIL only after software-delivery hashes exist.

## Release record

**Not released.**
