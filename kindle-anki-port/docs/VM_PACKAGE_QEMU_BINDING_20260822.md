# VM package/QEMU release binding hardening — 2026-08-22

## Scope

This continuation started from canonical branch head `90af58f26070f9ae144741d0785eab1e186c1563` after reading `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md`.

The audit focused on the last non-hardware release boundary between exact-rootfs QEMU evidence and package construction.

## Defect found

`run-qemu-smoke.sh` had already been hardened so a QEMU PASS was bound to the clean project `BUILD_COMMIT`, the pinned Anki commit, the canonical PW6 5.19.6 rootfs manifest, and the exact ARMHF binary hashes. However, `package-and-audit.sh` did not consume or validate any of that QEMU evidence.

That left a real release-provenance gap: an operator could produce a current ARMHF build and package it without having run exact-rootfs QEMU for those exact bytes, or could accidentally package after a stale QEMU run. The release directory also omitted the QEMU evidence that the completion rule expects to persist.

A second issue was that `QEMU-PROVENANCE.txt` recorded absolute `ROOTFS` and manifest paths. If the release evidence is persisted publicly, those host-specific paths can disclose local directory names without adding cryptographic value.

## Production changes

### `testenv/scripts/package-and-audit.sh`

Packaging is now fail-closed unless `QEMU` points to a completed `run-qemu-smoke.sh` output directory containing:

- `QEMU-SMOKE.txt` with exact line `QEMU smoke: PASS`;
- `QEMU-PROVENANCE.txt`;
- `rootfs-verification.txt` containing exact `PW6 rootfs verification: PASS`;
- `backend-smoke.txt` containing exact `qemu backend smoke: ok`;
- `audio-self-test.txt` containing exact `kap-audio self-test: ok`;
- `sync-self-test.txt` containing exact `kap-sync self-test: ok`.

The package gate then requires QEMU provenance to match:

- current package `BUILD_COMMIT`;
- pinned `upstream.lock.json` Anki commit;
- SHA-256 of the committed canonical PW6 5.19.6 manifest;
- SHA-256 of all four ARMHF release binaries: `libanki-kindle.so`, `kap-app`, `kap-audio`, and `kap-sync`.

Any mismatch exits `66` before package staging is rebuilt.

Successful packaging now copies the six QEMU evidence files into the release directory and adds `rootfs_manifest_sha256` plus `qemu_provenance_sha256` to `PACKAGE-PROVENANCE.txt`.

Current blob:

```text
testenv/scripts/package-and-audit.sh  930a4128adf6e754f58a7f55da8014e59b90b122
```

### `testenv/scripts/run-qemu-smoke.sh`

QEMU provenance is now path-sanitized. It records the stable manifest identity/hash and verification state instead of absolute rootfs/manifest paths:

```text
rootfs_manifest_id=pw6-5.19.6-rootfs-manifest.json
rootfs_manifest_sha256=<sha256>
rootfs_verified=true
```

If `ROOTFS_IMAGE` is supplied, only its SHA-256 is recorded. Absolute rootfs paths are no longer persisted.

Current blob:

```text
testenv/scripts/run-qemu-smoke.sh  ac595dbeb6c411b51751953eef9b9400afe5a166
```

## Regression coverage

`tests/test_package_reproducibility.py` now constructs matching synthetic QEMU evidence, passes `QEMU` into the production package script, verifies the QEMU reports are persisted, and covers these fail-closed cases:

- stale QEMU `source_commit`;
- wrong QEMU `anki_commit`;
- stale QEMU ARMHF binary hash;
- `QEMU-SMOKE.txt` not PASS.

It also verifies `PACKAGE-PROVENANCE.txt` records the rootfs manifest hash and QEMU provenance hash.

`tests/test_qemu_provenance.py` now asserts the generated provenance includes the canonical manifest ID and `rootfs_verified=true`, while excluding the private rootfs absolute path.

Current blobs:

```text
tests/test_package_reproducibility.py  9b85781c6a4738b117da5ff218276c373089aa55
tests/test_qemu_provenance.py           c3ccf143be655f2638770b5c5ea7f012d384c037
```

Both tests remain part of `run-static-gates.sh`; no separate gate wiring was needed.

## Targeted VM evidence

The direct execution container still cannot resolve `github.com`, so a complete canonical checkout and full static/backend/ARMHF build could not truthfully be rerun here. The failed materialization probe was:

```sh
git clone --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki
# rc=128
# fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
```

The changed production scripts and regression source were nevertheless exercised with isolated deterministic fixtures.

Syntax/compile checks:

```sh
bash -n /tmp/qemu-new.sh
bash -n /tmp/package-new.sh
python3 -m py_compile /tmp/test_package_reproducibility_new.py
```

All passed.

A synthetic end-to-end package run with matching ARMHF/QEMU provenance returned `0`, produced a valid ZIP, and persisted all QEMU sidecars. Synthetic archive SHA-256:

```text
1d518583b1bae606885be4873bc3fa1528f826ac0ab77fd9453d8b676e5fa067
```

This is test evidence only, not a release artifact.

Negative targeted results:

```text
stale QEMU source_commit       rc=66
stale kap-app QEMU hash        rc=66
QEMU-SMOKE.txt = FAIL          rc=66
```

A synthetic QEMU run also passed and confirmed the generated provenance contains no rootfs absolute path. Its synthetic `QEMU-PROVENANCE.txt` SHA-256 was:

```text
20d2980edd56c20f0763532e1f4b26ab4afc5a6fe7827b17a9fdc1a79625a84f
```

Persisted targeted log:

```text
docs/logs/KAP_PACKAGE_QEMU_BINDING_20260822.log
Git blob: a747193fee7ce4f6fd942f0b67bea66e8d37fea8
SHA-256: 97fa62623ae4e940f8963b2bc3e15649306f413bbf441411dc950ca61af2e9be
```

## Material commits

```text
a974f87f57ac83dd7ef3e042f9866b1c5aa7fc22  fix: sanitize exact-rootfs QEMU provenance
ae94c42917e73a438232474276ff2ae15523e37e  fix: require exact-rootfs QEMU evidence for release packaging
7c61902cc9f5025569a146fb89ac1d1a845efcf6  test: bind package reproducibility to QEMU provenance
7b65b0ba32642d4c77d665a6e9d39d242dcbfbb4  test: keep QEMU provenance path-sanitized
5014ce83c3d6d0e63e87af8c12e9b803f7458e85  test: persist package QEMU binding evidence
```

## Release implication

The earlier ZIP `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225` remains a stale checkpoint. It predates this package/QEMU binding and cannot satisfy the current production package gate.

A final package can now only be produced after a fresh exact-rootfs QEMU PASS for the exact ARMHF bytes being archived. This turns the intended release ordering into an enforced invariant instead of documentation-only policy.

## Next actions

1. Materialize the then-current branch head in a network-capable build VM.
2. Run full static gates from the clean head, including the updated package/QEMU provenance regressions.
3. Rerun official Anki `rslib`, five real APKG integrations, ARMHF build, ABI/GLIBC audits from the same head/pin.
4. Supply the checksum-matching private PW6 5.19.6 rootfs and run `run-qemu-smoke.sh` against those fresh ARMHF outputs.
5. Only after that QEMU PASS, run `package-and-audit.sh` with `QEMU=<fresh qemu output>` and persist the final ZIP, external SHA-256, manifest, contents, build/QEMU/package provenance, and complete test report.
6. Keep physical PW6 HIL acceptance separate; VM/QEMU evidence does not satisfy it.
