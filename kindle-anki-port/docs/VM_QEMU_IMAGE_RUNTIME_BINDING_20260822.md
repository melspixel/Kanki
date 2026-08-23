# VM report — QEMU runtime bound to retained PW6 image

Date: 2026-08-22 UTC

## Scope

This checkpoint audits the exact-rootfs L2 gate after the earlier change that made `ROOTFS_IMAGE` mandatory.

## Defect found

The previous `run-qemu-smoke.sh` verified the retained image SHA-256, but still executed QEMU with `-L "$ROOTFS"`, where `ROOTFS` was an independently supplied extracted directory. `verify-pw6-rootfs.py` verifies the image hash plus selected loader/libc/WebKit/version oracles in the directory; it does not prove every runtime file in that caller-supplied directory came from the retained image.

Therefore a caller could pair the canonical retained image with a different extracted tree that happened to contain the pinned oracle files. The full image hash would be correct while QEMU could still resolve other shared objects from bytes not derived from that image. This made the previous `rootfs_image_sha256` provenance stronger than the actual runtime identity.

A second freshness issue existed in the same script: a failed dynamic rerun could leave an older `QEMU-SMOKE.txt` and `QEMU-PROVENANCE.txt` in a reused output directory.

## Fix

`testenv/scripts/run-qemu-smoke.sh` now:

1. still requires and verifies both the supplied extracted rootfs and retained image;
2. invalidates prior dynamic QEMU evidence before a new L2 attempt starts;
3. requires `debugfs`;
4. creates a private temporary directory and runs `debugfs -R "rdump / <temp-rootfs>" <ROOTFS_IMAGE>`;
5. verifies that image-derived tree with the canonical verifier;
6. runs backend/audio/sync QEMU only with `-L <image-derived-rootfs>`;
7. records `rootfs_input_verified=true` and `rootfs_runtime_source=verified-image-rdump` in `QEMU-PROVENANCE.txt`;
8. writes `QEMU-SMOKE.txt` only after all runtime checks pass.

`testenv/scripts/package-and-audit.sh` now rejects pre-hardening QEMU evidence. It requires:

```text
input-rootfs-verification.txt
rootfs_input_verified=true
rootfs_runtime_source=verified-image-rdump
```

and copies both supplied-tree and image-derived verification reports into the release evidence. `PACKAGE-PROVENANCE.txt` records the same runtime-source invariant.

Tests were updated so the QEMU fixture provides a fake `debugfs`, records QEMU argv and proves `-L` does not point at the caller-supplied rootfs. A second regression runs L2 successfully once, forces the image-derived extraction step to fail on the next attempt, and proves the old PASS/provenance files are removed. Package reproducibility fixtures now also reject a false `rootfs_input_verified` value or non-image-derived runtime source.

## Commits

```text
b304c28bf82e8713e1b91fb859fa2dbabfa9e364  qemu: execute against rootfs re-extracted from verified image
0133be7afd7ad0b0f5f2f76c54626c266721efe1  package: require image-derived QEMU runtime provenance
f5e744212f2de9645a27ada167ae5032bb8ee8d6  test: cover image-derived QEMU runtime binding
53f7a8cb53e54002b19b00be05f70d8d41f38840  test: bind package fixtures to image-derived QEMU runtime
1d6dc39af6a767daf2d6bbb00e9af1b550434113  test: persist image-derived QEMU provenance regression log
```

Current blobs after the code/test changes:

```text
testenv/scripts/run-qemu-smoke.sh      0a785125c0afa5957ae0c5115dd91ddd7ba896c9
testenv/scripts/package-and-audit.sh   524bbe1dc914b18eb146b5266a14794ddd0abe4f
tests/test_qemu_provenance.py          e1be1b7c5d4dc0a9bf747f8693ed4f2b3604b1a2
tests/test_package_reproducibility.py  d554df6aea2c90e80b379b366eb3f43664281bf9
```

## Targeted validation

Normal repository materialization remains unavailable in this execution container:

```sh
rm -rf /tmp/Kanki && \
git clone --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki
```

Result:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

Because the complete tree could not be cloned, this checkpoint did not claim a full current-head static/backend/ARMHF build. The changed production QEMU logic and exact updated QEMU regression fixture were reconstructed in an isolated local fixture and run with:

```sh
python3 /tmp/kap-targeted/tests/test_qemu_provenance_exact.py \
  2>&1 | tee /tmp/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log
bash -n /tmp/kap-targeted/testenv/scripts/run-qemu-smoke.sh
sha256sum /tmp/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log
```

Result:

```text
.........
----------------------------------------------------------------------
Ran 9 tests in 10.984s

OK
```

Persisted log:

```text
docs/logs/KAP_QEMU_IMAGE_RUNTIME_TARGETED_20260822.log
SHA-256 985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac
```

The targeted run covers matching provenance, image-derived `-L`, stale PASS invalidation, absent/non-file image, stale source provenance, wrong Anki provenance, non-PASS ARMHF gate, alternate manifest bytes and dirty source tree.

## Release impact

All older exact-rootfs QEMU evidence is intentionally stale for final packaging because it lacks `rootfs_runtime_source=verified-image-rdump`. This is a release-hardening checkpoint, not a release.

The historical installer remains stale:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Next actions

1. Materialize the newest clean branch head in a network-capable build VM.
2. Ensure `e2fsprogs/debugfs` is installed alongside the existing host/ARM/QEMU dependencies.
3. Run complete static gates, including the updated 9-case QEMU provenance suite and package reproducibility suite.
4. Run the pinned official Anki 26.08.1 backend and five real APKG integrations from that same source identity.
5. Run fresh ARMHF hard-float plus ELF/ABI/GLIBC/export audit.
6. Supply both checksum-matching private PW6 inputs. The retained image must be SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
7. Run exact-rootfs QEMU. The final QEMU provenance must contain `rootfs_runtime_source=verified-image-rdump`; QEMU must execute against the temporary tree re-extracted from that exact image.
8. Only after that PASS, run package/reproducibility/privacy/content gates and persist the final ZIP/checksum/manifest/contents/reports.
9. Physical PW6 HIL remains a separate final gate.
