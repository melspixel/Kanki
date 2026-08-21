# VM continuation — exact-rootfs QEMU release-provenance hardening (2026-08-22)

## Scope

This continuation audited the exact-rootfs QEMU release gate after the host/ARMHF source-identity preflight was hardened. The goal was to determine whether a future `QEMU smoke: PASS` would be cryptographically and semantically tied to the same canonical project/Anki/ARMHF inputs as the final release.

The full official Anki/ARMHF build was **not** rerun in this execution environment because direct Git networking is still unavailable. The failure remains reproducible:

```text
git ls-remote https://github.com/melspixel/Kanki.git refs/heads/kindle-anki-port
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
status=128
```

No prior ARMHF/package checkpoint is promoted by this report.

## Defect found

Before this hardening, `testenv/scripts/run-qemu-smoke.sh` verified the supplied rootfs contents and required `ARMHF/libanki-kindle.so`, but it did not verify that the supplied ARMHF directory belonged to the current release source commit or to the pinned Anki checkout. It also allowed `ROOTFS_MANIFEST` to point at arbitrary manifest bytes.

That created two false-release-evidence paths:

1. a stale ARMHF build from an older source commit could be run successfully against the exact rootfs and produce `QEMU smoke: PASS`, while a newer package was later built from a different source commit;
2. a caller could override `ROOTFS_MANIFEST` with a different manifest and obtain a rootfs verification/QEMU checkpoint that was not the committed PW6 5.19.6 runtime oracle.

Both violate the release definition, which requires exact-rootfs QEMU evidence from the same canonical source and ARMHF build that is being released.

## Production fix

`testenv/scripts/run-qemu-smoke.sh` now fails closed before QEMU execution unless all of the following hold:

```text
BUILD_COMMIT is a full lowercase 40-hex Git commit
PROJECT is a Git checkout
PROJECT HEAD == BUILD_COMMIT
PROJECT subtree is clean, including untracked source
upstream.lock.json contains a valid pinned Anki commit
ROOTFS_MANIFEST bytes == canonical pw6-5.19.6-rootfs-manifest.json bytes
ARMHF-GATES.txt exists and is exactly: ARMHF gates: PASS
BUILD-PROVENANCE.txt source_commit == BUILD_COMMIT
BUILD-PROVENANCE.txt anki_commit == upstream.lock.json commit
```

The QEMU gate also now persists the rootfs verifier stdout in `rootfs-verification.txt`, records `source_commit` and `anki_commit`, records the canonical rootfs-manifest SHA-256, and records SHA-256 values for `libanki-kindle.so`, `kap-app`, `kap-audio`, and `kap-sync` in `QEMU-PROVENANCE.txt`. If a rootfs image is supplied, its SHA-256 is recorded as well.

This does not replace the existing checksum verification inside `verify-pw6-rootfs.py`; it binds that verification to the canonical release inputs.

## Regression coverage

Added `tests/test_qemu_provenance.py` and wired it into `testenv/scripts/run-static-gates.sh` for both `py_compile` and execution.

The fixture uses an isolated temporary Git project plus fake QEMU/toolchain commands, so it can verify release-provenance policy without proprietary PW6 bytes. Six cases are covered:

```text
canonical clean project + matching ARMHF provenance + canonical manifest -> PASS
stale ARMHF source_commit                                      -> reject 66
wrong ARMHF anki_commit                                       -> reject 66
ARMHF-GATES.txt without PASS                                  -> reject 66
alternate ROOTFS_MANIFEST bytes                               -> reject 66
dirty project source tree                                     -> reject 66
```

Targeted commands:

```text
bash -n testenv/scripts/run-qemu-smoke.sh
python3 -m py_compile tests/test_qemu_provenance.py
python3 tests/test_qemu_provenance.py -v
```

Targeted result:

```text
6 tests; OK
```

Persisted regression log:

```text
docs/logs/KAP_QEMU_PROVENANCE_20260822.log
SHA-256: 1d217650cb8130e61a114c85fb808de0251ae308f257b35100065e57f7f1e21e
Git blob: 13673d812ae9068faa1a964c18bc276ab3623b84
```

The production script bytes used by the targeted fixture match the persisted Git blob. Content checksum:

```text
testenv/scripts/run-qemu-smoke.sh
Git blob: 0cfd348700e9f28a372e91864a1670cd97587e83
SHA-256: 2d2e3aead34b1aa3485d2f908d549d5207eede42db20fb39c71b1780f8502ec2
```

Other current blobs:

```text
tests/test_qemu_provenance.py             160f3e08b55638857876aabfffc1b09a99e65fa6
testenv/scripts/run-static-gates.sh       df2b9f4c476f1478c15555ed619230ea2d79433c
```

## Material GitHub commits

```text
a61421de2b21784b220ed91be82a6bee7c0354a5  fix: bind QEMU smoke to release provenance
2e022b6774782537605b5eb7a4b6c0525668257d  test: cover QEMU release provenance
2c0b36e1d82f70e7af3b2e784badf53bcf6f4944  test: gate QEMU release provenance
f10604db58b5160792799f00079214be40141f7b  test: persist QEMU provenance regression log
```

## What this does and does not prove

This proves the QEMU release gate will no longer accept stale ARMHF provenance or a noncanonical PW6 manifest, and that its future PASS evidence will contain enough hashes to associate the tested binaries with the release record.

It does **not** constitute an exact-rootfs QEMU run. The checksum-matching PW6 5.19.6 firmware/rootfs bytes are still not mounted in this VM. It also does not replace the required final clean-head rerun of static gates, official Anki `rslib`, five real APKG integrations, ARM hard-float cross-build, ABI/GLIBC audit, package audit, and final package reconstruction.

The old package SHA-256 `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225` remains a stale checkpoint only.

## Ordered next actions

1. Materialize the latest `kindle-anki-port` branch head in a build VM with the pinned Anki checkout, offline Cargo cache, protoc, and KindleHF toolchain.
2. Run the complete static gate, now including `test_qemu_provenance.py`.
3. From that same clean commit, rerun full official `rslib`, five-real-APKG integration, ARMHF cross-build, and ABI/GLIBC audit.
4. Supply the checksum-matching PW6 5.19.6 rootfs privately and run the canonical verifier plus the newly provenance-bound `run-qemu-smoke.sh` against the fresh ARMHF outputs.
5. Only after those gates are green, run `package-and-audit.sh` from the same source commit and persist the final ZIP, SHA-256, internal manifest, package contents, ARMHF/QEMU provenance, ABI/GLIBC outputs, and complete test report on GitHub.
6. Keep PW6 hardware-in-the-loop acceptance as a separate final gate; VM/QEMU results must not be promoted to a physical-device PASS.
