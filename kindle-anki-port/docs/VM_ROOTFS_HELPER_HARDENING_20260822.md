# VM PW6 firmware/rootfs helper hardening

Date: 2026-08-22 UTC

## Scope

This continuation audited the newly added shell convenience wrapper around the already-canonical Python PW6 rootfs preparation pipeline. The shell wrapper is not a substitute for `prepare-pw6-rootfs.py`; it exists to make checksum-pinned acquisition/extraction easier while preserving the same private-input boundary.

Starting commits:

```text
32b166ca650b04086f970e0b92d83a602f7b879e  testenv: add reproducible PW6 firmware-to-rootfs preparation
e4103bc5fb3c65d75c4bb22b5c4ca5358a9b8320  test: validate pinned PW6 rootfs preparation helper
```

## Defects found

### 1. Manifest key mismatch

`prepare-pw6-rootfs.sh` read:

```text
firmware.package_sha256
```

but the canonical manifest stores:

```text
firmware.sha256
firmware.md5
```

As written, even `--print-sources` would fail while indexing a non-existent JSON key.

### 2. The new test invoked a non-executable file directly

The helper was initially added to GitHub with mode `100644`, while `test_rootfs_prepare_script.py` attempted to execute it as a program. The test now invokes it explicitly with `sh`, so the regression does not depend on mode preservation. The repository helper itself was then corrected to mode `100755` in a tree-level commit so normal direct invocation also works.

### 3. Shell helper did not verify the pinned firmware MD5

The existing canonical Python pipeline verifies both SHA-256 and MD5 before external extraction tools run. The shell wrapper only verified SHA-256. It now validates both values from the canonical manifest, including the downloaded temporary file before it is moved into the requested firmware path.

### 4. Automatic fallback source was broader than the required provenance boundary

The first version fell back from Amazon to a community mirror. The helper now uses only:

```text
https://www.amazon.com/update_KindlePaperwhite_12th_Gen_2024
https://s3.amazonaws.com/firmwaredownloads/update_kindle_all_new_paperwhite_12th_5.19.6.bin
```

The second URL is the pinned Amazon firmware object. A downloaded file is accepted only after both pinned checksums match.

## Fixes

Canonical commits:

```text
cea5f6ae0be998f0426292a2da0f38a706d9fb2d  fix: correct pinned PW6 firmware helper verification
1c59968cd8af1fc4182a51c59e6c31562dc94597  test: enforce PW6 helper hashes and shell invocation
b1ed8a74d289ee0cf37005d924392a0352ebe8c6  test: gate PW6 firmware helper validation
335817498abaebe8f14a6454ffcf4e7f303e5be5  testenv: mark PW6 rootfs helper executable
```

Canonical Git blobs after the content changes:

```text
testenv/scripts/prepare-pw6-rootfs.sh  d01b1d02ced887592926deb5de586b6f40a0a3f0  mode 100755
tests/test_rootfs_prepare_script.py    d7399aa70688b6128c61a916ff9dd8e758de94f3
testenv/scripts/run-static-gates.sh    0c79c69f57f9506d6a2239e76cb4ee767476fcec
```

The static gate now syntax-checks the shell helper, byte-compiles the Python test, and runs the helper test suite.

## Targeted validation

The changed helper, test and canonical manifest were reconstructed in the isolated execution environment and run with:

```sh
sh -n testenv/scripts/prepare-pw6-rootfs.sh
python3 tests/test_rootfs_prepare_script.py
```

Result:

```text
Ran 3 tests in 6.816s
OK
```

The tests cover:

- exact Amazon alias/direct-object strings and pinned SHA-256/rootfs SHA-256;
- pinned firmware MD5 output;
- absence of an automatic community-mirror fallback;
- SHA-256 rejection before KindleTool/debugfs;
- MD5 rejection before KindleTool/debugfs;
- invocation through `sh`, while the repository also preserves executable mode for normal use.

Content SHA-256 values of the tested reconstruction:

```text
prepare-pw6-rootfs.sh         ca191215e97cc75d3945531c370e47d769ede74513fa44caf3a140d0744829bc
test_rootfs_prepare_script.py c5cdfc42e7de248ba90f0ffda1a71cfbb93df14c1894ed4068bb021b05e18500
```

These are content checksums for the tested reconstruction; the Git blob IDs above are the canonical repository identities.

## Remaining boundary

No firmware or rootfs bytes were acquired in this continuation, so exact-rootfs QEMU smoke remains pending. The required external firmware identities are unchanged:

```text
firmware SHA-256 72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
firmware MD5     697aeb33c02f46b9b0911ab05c28b06d
rootfs SHA-256   b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

A checksum-passing shell helper is preparatory evidence only. It does not satisfy the release requirement until the real checksum-matching private bytes are available and `verify-pw6-rootfs.py` plus `run-qemu-smoke.sh` pass against them.
