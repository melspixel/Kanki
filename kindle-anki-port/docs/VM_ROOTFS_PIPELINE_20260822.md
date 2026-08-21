# VM checkpoint — checksum-pinned PW6 rootfs preparation

Date: 2026-08-22 UTC

## Purpose

Close the gap between the committed PW6 5.19.6 runtime manifest and the exact-rootfs QEMU smoke gate without placing Amazon firmware or rootfs bytes in GitHub.

## Added implementation

`testenv/scripts/prepare-pw6-rootfs.py` now provides one deterministic pipeline:

1. verify the official firmware SHA-256 and MD5 against `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`;
2. invoke KindleTool to extract the firmware package;
3. require exactly one rootfs image candidate;
4. inflate `rootfs.img.gz` when necessary;
5. verify the rootfs-image SHA-256 before filesystem extraction;
6. extract the filesystem with `debugfs rdump`, avoiding a privileged mount;
7. run `verify-pw6-rootfs.py` against the loader, libc, WebKit, firmware-version and GLIBC oracle;
8. write a provenance JSON outside the extracted rootfs;
9. remove partial output after hash, extraction or verification failure;
10. delete the private work directory unless `--keep-work` is explicitly requested.

The tool refuses to overwrite a non-empty destination and never writes firmware/rootfs bytes into the source tree.

## Deterministic fixture test

`tests/test_prepare_pw6_rootfs.py` uses synthetic firmware, a synthetic gzip-compressed rootfs image, a synthetic runtime tree, fake KindleTool and fake debugfs executables. It verifies:

- successful extraction and provenance recording;
- target runtime file verification through the existing verifier;
- refusal to overwrite an existing rootfs;
- firmware SHA-256 rejection before extraction;
- rootfs-image SHA-256 rejection;
- partial-output cleanup after failure.

Executed in the VM:

```text
python3 tests/test_prepare_pw6_rootfs.py
test_prepare_pw6_rootfs: ok
```

The exact locally executed Git blob identities are:

```text
testenv/scripts/prepare-pw6-rootfs.py  dad0345d6ad56b17fc7764b1ce0d69a3ed637be8
tests/test_prepare_pw6_rootfs.py        bd503d5842720c054531b3ca60ec708cd27de0eb
```

`testenv/scripts/run-static-gates.sh` now compiles both rootfs scripts and executes the preparation fixture as part of the canonical static gate.

## Commits

```text
477df23b2db90422660c34309eb8798f0b536e1f  testenv: add checksum-pinned PW6 rootfs preparation pipeline
d086bc2c4b22636a76de450735481316cb754b47  test: cover checksum-pinned PW6 rootfs preparation
3be9b9bf72f0a7e88066f0c774caa454b79eeb42  testenv: gate PW6 rootfs preparation and verification
ef064fe91d618a8f1ac15f70fa68ab7881ffffcf  test: align checked rootfs fixture source with verified VM copy
```

## Remaining gate

The extraction/verification path is now implemented and deterministically tested. The exact-rootfs QEMU gate is still pending the external, checksum-matching PW6 5.19.6 firmware bytes plus executable `kindletool` and `debugfs` in the build VM. Derived oracle reports are not treated as substitutes for the runtime bytes.

No user collection, media, credential, device serial, firmware or rootfs content is present in this checkpoint.
