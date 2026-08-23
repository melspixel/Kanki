# VM build provenance hardening — 2026-08-22

## Scope

This continuation audited the release-build entry points after the package provenance regression work. The direct VM still could not resolve `github.com`, so a normal canonical clone/full Anki/toolchain rebuild was not truthfully available in this execution environment. The work below therefore hardens and targeted-tests source identity preflight; it is not a replacement for the required full canonical-head backend/ARMHF/QEMU/package rerun.

Starting canonical branch head observed through GitHub:

```text
90a09e142219d83d73176034be4084b7d0814c57
```

Direct clone attempt:

```sh
rm -rf /tmp/Kanki
git clone --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki
```

Result:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/':
Could not resolve host: github.com
status=128
```

## Defect found

`testenv/scripts/run-armhf-gates.sh` previously stamped `BUILD-PROVENANCE.txt` with a project commit and the pinned Anki commit, but it did not prove that the bytes actually being compiled came from those identities.

Two false-provenance paths therefore existed:

1. a dirty `kindle-anki-port/` working tree could be compiled, then cleaned/reverted before packaging; the stale ARMHF binaries could still claim the unchanged project `HEAD`;
2. `$ANKI` could point at a different Anki checkout while `BUILD-PROVENANCE.txt` still recorded the commit read from `upstream.lock.json`.

`package-and-audit.sh` already compared ARMHF provenance text to the package source commit and Anki pin, but it could not detect either case because the incorrect identity was written before packaging.

The same weakness existed in `run-host-backend-gates.sh`: a dirty project tree or wrong Anki base could produce a green host semantic checkpoint before any immutable identity check.

## Fix

`run-armhf-gates.sh` now fails before Cargo/toolchain execution unless all of the following hold:

```text
BUILD_COMMIT is lowercase full 40-hex
PROJECT is a Git checkout
PROJECT HEAD == BUILD_COMMIT
PROJECT subtree is clean, including untracked source files
upstream.lock.json commit is lowercase full 40-hex
ANKI_COMMIT, if supplied, == upstream.lock.json commit
ANKI is a Git checkout
ANKI HEAD == upstream.lock.json commit
```

Exit policy:

```text
65 invalid provenance syntax/pin
66 project source identity/cleanliness failure
67 Anki source identity failure
```

The Anki working tree itself is intentionally not required to be clean because `inject_into_anki.py` overlays the maintained semantic bridge into the pinned checkout before backend compilation. Its immutable base `HEAD` must still equal the lock-file pin.

`run-host-backend-gates.sh` now performs the corresponding project and Anki identity preflight before `inject_into_anki.py` is allowed to run.

## Regression coverage

Two deterministic tests were added and wired into `testenv/scripts/run-static-gates.sh`:

```text
tests/test_armhf_provenance.py
tests/test_host_backend_provenance.py
```

ARMHF fixture cases:

```text
clean pinned project + Anki -> reaches fake cargo sentinel
invalid BUILD_COMMIT -> 65 before cargo
mismatched project HEAD -> 66 before cargo
dirty project source -> 66 before cargo
ANKI_COMMIT override != lock -> 67 before cargo
Anki checkout HEAD != lock -> 67 before cargo
```

Host-backend fixture cases:

```text
clean pinned project + Anki -> injector + cargo check/test/build + export fixture PASS
invalid BUILD_COMMIT -> 65 before injection
mismatched project HEAD -> 66 before injection
dirty project source -> 66 before injection
Anki checkout HEAD != lock -> 67 before injection
```

## Targeted execution evidence

The exact current ARMHF gate and ARMHF regression source were reconstructed byte-for-byte from the GitHub-authored contents into the isolated VM and checked with:

```sh
bash -n testenv/scripts/run-armhf-gates.sh
python3 -m py_compile tests/test_armhf_provenance.py
python3 tests/test_armhf_provenance.py
```

Result:

```text
......
----------------------------------------------------------------------
Ran 6 tests in 4.343s

OK
```

SHA-256:

```text
ARMHF targeted log       2ee0b646827cbeb83d05ea7572ad526d914826f4d480b5b485b2633edb17d538
run-armhf-gates.sh       accc8789fb13e82befe35d8ba96d124869ef2aebd9a788e41259936f1f61122f
test_armhf_provenance.py 64b98e1b7e2d2746b1ce667036eb3ed71164430f2d54936c549b1dd492585bc5
```

Git blob identities at the tested branch state:

```text
run-armhf-gates.sh       a81e8017034ba707aa0fca93248f44ec6c87dc1b
test_armhf_provenance.py ba206860e3dc47739fd3a2a02c4e542ce7f75eb6
```

The exact current host-backend gate and host regression source were likewise reconstructed and checked with:

```sh
bash -n testenv/scripts/run-host-backend-gates.sh
python3 -m py_compile tests/test_host_backend_provenance.py
python3 tests/test_host_backend_provenance.py
```

Result:

```text
.....
----------------------------------------------------------------------
Ran 5 tests in 4.140s

OK
```

SHA-256:

```text
host targeted log                897fd9ac46cc311276d31218d58a50cec190cad6582ebc518be803ccf2365db4
run-host-backend-gates.sh        9417e59ea54618397834a022420a0880807da350bc1d061e518890e94af2260c
test_host_backend_provenance.py  36dfd4917a7d0db878e13a436812d8990d9ec1743262fcdfa157d6176f8f07ee
```

These targeted tests validate the new preflight behavior without pretending to exercise official Anki compilation or the KindleHF toolchain.

## Material commits

```text
9102530fb36eadb613cf2d222b363be7e1602992  build: bind ARMHF gates to canonical source identities
dd6b52f8c2d632729763a3fbd31dcd6d93a0219c  test: enforce ARMHF source provenance preflight
d502fbfd77d983a957fa5f9eb1a8ee575e3b03bd  test: gate ARMHF provenance preflight
8dd11fb2d36eceedfece835b3c95680701195459  test: isolate ARMHF provenance preflight from toolchain lookup
94cb12917ed6bebfa8b712f4bee87a983b4c39d5  build: bind host backend gates to canonical source identities
b33069af1bda1cc6c21499210a2d2fc0deca23f9  test: enforce host backend source provenance preflight
f274e1107776e35136c3627da2677216ca3cb8fe  test: gate host backend provenance preflight
```

## Release impact

The older ARMHF and ZIP checkpoints remain valid historical test evidence but are even more clearly non-release provenance: they predate this fail-closed source-identity preflight. No existing binary was relabeled as current.

The next network-capable build VM must check out the then-latest branch head and rerun, from that same clean commit:

```text
complete static gates
full official Anki 26.08.1 rslib check/test/release build
five real APKG integration
ARM hard-float cross-build
ELF / ABI / GLIBC audit
package-and-audit.sh
```

After checksum-matching PW6 5.19.6 private rootfs bytes are available, the same release candidate must then pass exact-rootfs QEMU smoke before final ZIP/report persistence. Physical PW6 acceptance remains a separate hardware gate.
