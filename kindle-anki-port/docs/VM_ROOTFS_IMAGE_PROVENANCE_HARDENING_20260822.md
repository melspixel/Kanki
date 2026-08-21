# VM rootfs-image provenance hardening — 2026-08-22

## Scope

This continuation began from live branch head `97ee84d3596baf456d0dadacafa1443dffdee253` and first read the required continuation state (`HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, `docs/TEST_ENVIRONMENT.md`). The work below is release-provenance hardening while ordinary Git materialization remains unavailable in the execution container and the private PW6 runtime is not mounted.

## Defect found

The canonical PW6 manifest already pins the full extracted rootfs-image SHA-256:

```text
b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

and `verify-pw6-rootfs.py` already verifies that value **when** `--rootfs-image` is supplied. However, the production exact-rootfs gate made the image optional:

```text
run-qemu-smoke.sh
  ROOTFS_IMAGE was optional
  verifier received --rootfs-image only when the variable was set
  QEMU-PROVENANCE.txt recorded rootfs_image_sha256 only when present
```

Therefore an extracted directory could satisfy L2 with only the selected canonical loader/libc/WebKit hashes plus firmware version files. That proves important runtime bytes, but it does not cryptographically identify the complete root filesystem. Unchecked files in the extracted tree could differ from the canonical image while the gate still emitted `QEMU smoke: PASS`.

The same weakness propagated outward: `package-and-audit.sh` did not require `rootfs_image_sha256`, the top-level/testenv Makefiles did not require or propagate the retained image, and `vm-advance.py --rootfs` did not require `--rootfs-image`.

This contradicted the maintained phrase “exact checksum-matching PW6 rootfs QEMU”.

## Production fix

### `run-qemu-smoke.sh`

L2 now fails closed unless `ROOTFS_IMAGE` names a regular retained image. The verifier is always invoked as:

```sh
python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" \
  "$ROOTFS" --manifest "$ROOTFS_MANIFEST" --rootfs-image "$ROOTFS_IMAGE"
```

and successful QEMU provenance always contains:

```text
rootfs_verified=true
rootfs_image_sha256=<actual retained image SHA-256>
```

Only hashes/identifiers are persisted; the private image/rootfs path is not written to `QEMU-PROVENANCE.txt`.

### `package-and-audit.sh`

Before any staging/ZIP work, L2.5 now independently requires all of the following:

```text
QEMU-PROVENANCE.txt rootfs_verified=true
QEMU-PROVENANCE.txt rootfs_image_sha256 == manifest rootfs_image.sha256
rootfs-verification.txt contains:
  rootfs image sha256: PASS b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

`PACKAGE-PROVENANCE.txt` now records the canonical `rootfs_image_sha256` in addition to manifest/QEMU/archive hashes.

### Maintained entrypoints/orchestrator

- top-level `Makefile`: adds `ROOTFS_IMAGE`, requires it for `qemu-smoke`, passes it to the production gate;
- `testenv/Makefile`: propagates `ROOTFS_IMAGE`;
- `vm-advance.py`: `--rootfs` now requires `--rootfs-image`, verifies it is a file, records only its SHA-256 in `report.json`, and always propagates it to L2;
- `tests/test_build_entrypoints.py` and `tests/test_vm_advance_contract.py`: lock those contracts into static gates.

### Test fixtures

- `tests/test_qemu_provenance.py` now supplies a retained synthetic image, verifies its hash is recorded without leaking the path, and rejects absent/non-file `ROOTFS_IMAGE`;
- `tests/test_package_reproducibility.py` now supplies canonical synthetic rootfs-image evidence, checks package provenance records it, and rejects a stale/wrong QEMU rootfs-image hash;
- the pre-existing `tests/test_prepare_pw6_rootfs.py` already includes a tampered-image negative case at preparation/verifier level.

### Policy/docs

The rootfs tree + retained image pair is now explicit in:

```text
docs/TEST_ENVIRONMENT.md
testenv/README.md
docs/RELEASE_GATES.md
VM_RUNBOOK.md
CODEX_COORDINATION.md
```

Codex/local Task B specifically requires `--keep-image`; `<PRIVATE_DIR>/pw6-rootfs.img` is no longer described as optional. Ordinary compilation/QEMU/package execution remains VM-owned.

## Git persistence

Production/test blobs after hardening:

```text
testenv/scripts/run-qemu-smoke.sh       21daca49e9908f2855754f133a9d221d29916d7f
testenv/scripts/package-and-audit.sh    0bd1f398e2165ee7da73318816466c4de2a1f282
Makefile                                f909aeb9152ffd36beaba5246034b128bc074895
testenv/Makefile                        8988b75883754700383665eb1b5dc9c49666e6e0
testenv/scripts/vm-advance.py           bdae4cc700eb390d1cf62eee33c29228caa68c80
tests/test_qemu_provenance.py           bc807b3adadae8b0b18b537818808c62f8fc1d31
tests/test_package_reproducibility.py   8d2dc69a6cf2673aa6cd6454bca2b6252e23cd79
tests/test_build_entrypoints.py         9ec13f75c8950a8c9bbd82cb41ae70f33f0e997f
tests/test_vm_advance_contract.py       f9b86756cd029208393ef5028a1766ec609be6f5
```

Policy blobs:

```text
docs/TEST_ENVIRONMENT.md   11016d272f34d248ad8919b521f133b6dd2e5088
testenv/README.md          372b305556cab6c09efe05a935c8203299c8c18d
docs/RELEASE_GATES.md      6ad2522d4f105edbf099febf585af8d96e0af086
VM_RUNBOOK.md              7bdb674f91157674c0cd2fb501662117d3c97651
CODEX_COORDINATION.md      85cae1a49ca21633c05fc37b32e328c6f259a0ba
```

Relevant commits in this hardening chain:

```text
c758062cc926636566b38f08e191749737739026  qemu: require exact PW6 rootfs image identity
9a0fb47ee54f6f599a1abe2857b9fef27df215f5  package: bind release to canonical rootfs image hash
7c0b349e17b82e0ba937aab599a31e68115d590e  test: require retained rootfs image for QEMU provenance
ae340fb5e4b658699773b750655f83c5620ee7fd  test: bind package fixture to canonical rootfs image hash
a216479dc178643a3621be340c28c935c684499e  build: require retained rootfs image for exact QEMU
4edf2f1e3757ccf1ba9d1a71509886391f25f8aa  build: propagate retained rootfs image in testenv Makefile
9b24b2f97e945cf530a7c32c08e8a7a1e37ebefc  test: lock rootfs image propagation at QEMU entrypoints
493abe64542af65a0440d166a0b4689fd60462ce  vm: require retained rootfs image for exact QEMU
5eafe9cca83b58abae086e2cacd3f2f682a376d3  test: lock vm rootfs image release identity
bdb6045121201991088acfc8995ba117c3bf8a09  docs: require full rootfs image identity at L2
c03201a6ccb976b26cf69319cb7e625fd6f8953a  docs: require retained rootfs image in testenv flow
f0873e5dd68e30554843aa389f9e971342aa0ea6  docs: bind release policy to retained rootfs image
b4da2ef26bdd1082781709e041f2304d2bcd312e  docs: require retained image in VM release runbook
9aa07a28d6f5438bff788b75a5bdcd4cd9acdc31  docs: make retained rootfs image mandatory in Codex task
de68846754ff278558c5a94ad4bb4b61f8e47182  test: persist rootfs image package-binding evidence
5fbb1b977bd1c15c72039eb299ec3221008c4fab  test: persist targeted rootfs image QEMU evidence
```

## Targeted validation performed in this execution container

A normal repository clone remains impossible because external DNS is unavailable:

```sh
rm -rf /tmp/Kanki-auto2
git clone --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki-auto2
```

Result:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

Therefore no fresh complete current-head static/backend/APKG/ARMHF build is claimed.

The rootfs-image portion of the QEMU gate was exercised with a self-contained synthetic Git/project/toolchain/QEMU fixture mirroring the production gate behavior. It covered a valid retained image, absent image, non-file image and stale ARMHF source provenance:

```text
test_missing_image ... ok
test_nonfile_image ... ok
test_ok ... ok
test_stale_source ... ok
Ran 4 tests
OK
```

Persisted log:

```text
docs/logs/KAP_ROOTFS_IMAGE_QEMU_TARGETED_20260822.log
SHA-256 ca9a95f5bacea22d190c507098d697f565d1e44a88dc5dfba556699f8e1782c3
```

The new L2.5 image-binding predicates were separately exercised against synthetic QEMU evidence using the exact comparison semantics added to `package-and-audit.sh`:

```text
matching_rootfs_image_rc=0
wrong_rootfs_image_rc=66
rootfs_verified_false_rc=66
missing_image_verification_marker_rc=66
```

Persisted log:

```text
docs/logs/KAP_ROOTFS_IMAGE_BINDING_20260822.log
SHA-256 8f38bd14c63e79de30b01d4d0122010680e276d2cc62f08a83e9c1289b540d5e
```

These are targeted regression checks only; they do not replace the complete static gate suite or production package reproducibility test from a fully materialized current tree.

## GitHub Actions observation

At checkpoint head `5fbb1b977bd1c15c72039eb299ec3221008c4fab`, canonical workflow run `32534150567` completed `failure`. Job `96931794076` again exposed no recorded steps. This is the same pre-step/unavailable-runner symptom seen earlier and provides no code-level diagnostic, so it is not counted as validation.

## Release status

**Not released.** The rootfs identity invariant is stronger, but the required release evidence has not been rerun from the latest clean source and the actual private rootfs tree/image pair is not mounted.

The stale historical installer remains invalid final evidence:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Ordered next actions

1. Materialize the then-current clean branch head in a build VM with pinned Anki/Cargo/protoc/KindleHF inputs.
2. Run complete static gates, including the updated QEMU/package/entrypoint/VM-driver fixtures.
3. From the same identity, rerun official Anki 26.08.1 backend tests plus all five real APKG integrations including typed answer.
4. Rebuild ARMHF and rerun ELF/ABI/GLIBC/export audit.
5. Supply **both** checksum-matching private inputs: extracted PW6 5.19.6 rootfs and retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e...5c5cfa`.
6. Run exact-rootfs QEMU with `ROOTFS` + `ROOTFS_IMAGE` for the fresh ARMHF bytes and persist the resulting full-image-bound QEMU evidence.
7. Only then run package/reproducibility/privacy/content audit and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
8. Record physical PW6 HIL separately after software-delivery hashes exist.
