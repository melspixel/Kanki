# Kindle Anki Port — package provenance regression repair, 2026-08-22

## Scope

This continuation started from canonical branch head:

```text
3001f4e1d9bfe91714bd76a21fbdbf32109fd1b0
package: bind release archive to ARMHF provenance
```

The build container again could not resolve `github.com`, so a normal public clone/fetch and the full pinned Anki/KindleHF build were not available in this execution environment. Ordinary compilation remains VM-owned; no local-host compilation task was created.

## Defect found

Commit `3001f4e1d9bfe91714bd76a21fbdbf32109fd1b0` correctly hardened `testenv/scripts/package-and-audit.sh` so a release archive cannot be relabelled from stale ARMHF outputs. The package script now requires:

```text
ARMHF-GATES.txt              exactly contains: ARMHF gates: PASS
BUILD-PROVENANCE.txt         source_commit=<BUILD_COMMIT>
BUILD-PROVENANCE.txt         anki_commit=<upstream.lock.json commit>
```

However, the already-gated reproducibility fixture in `tests/test_package_reproducibility.py` still synthesized both files as generic placeholder text:

```text
fixture:ARMHF-GATES.txt
fixture:BUILD-PROVENANCE.txt
```

Therefore the current static gate had become deterministically self-inconsistent: `test_package_reproducibility.py` would fail before it could exercise ZIP reproducibility because the fixture no longer satisfied the production package preconditions.

This is a test-fixture regression, not a reason to weaken the production provenance checks.

## Repair

`tests/test_package_reproducibility.py` now:

- reads the pinned Anki commit from `upstream.lock.json`;
- emits `ARMHF gates: PASS` in its synthetic `ARMHF-GATES.txt`;
- emits a structurally valid `BUILD-PROVENANCE.txt` with the synthetic source commit and real pinned Anki commit;
- adds explicit negative cases proving that a stale ARMHF `source_commit` is rejected with status `66`;
- adds an explicit negative case proving that a mismatched ARMHF `anki_commit` is rejected with status `66`;
- restores valid provenance before testing the existing `SOURCE_DATE_EPOCH` boundary behavior.

Material commit:

```text
03a4e00be7a9d31848879430cdb6046eb2a6e536
test: bind package reproducibility fixture to ARMHF provenance
```

Canonical test blob after the repair:

```text
286938ddf9ae5ee85972cebf97c52fa599ce2a67  tests/test_package_reproducibility.py
```

## Validation boundary

The failure is established directly from the production package predicates and the previous fixture bytes: the package script uses exact `grep -qx 'ARMHF gates: PASS'` plus parsed `source_commit`/`anki_commit` equality checks, while the old fixture generated neither required value.

A full execution of `run-static-gates.sh` is **not** claimed in this report because the execution container cannot materialize the repository through public DNS and no complete canonical checkout is mounted. The next network-capable build VM must run the actual gated test from the repaired head.

## Ordered next execution

1. Materialize canonical head `03a4e00be7a9d31848879430cdb6046eb2a6e536` or its then-current descendant in the build VM.
2. Run `testenv/scripts/run-static-gates.sh`; the package reproducibility fixture must now reach and pass both positive reproducibility cases and both stale-provenance rejection cases.
3. Continue from the same immutable head through full official Anki rslib tests, five-real-APKG C-ABI integration, ARMHF hard-float build, ABI/GLIBC audit, and `package-and-audit.sh`.
4. Run exact-rootfs QEMU only after checksum-matching PW6 5.19.6 private runtime bytes are available.
5. Regenerate the final package and reports only from the same source/ARMHF provenance that passed the release gates.

No release completion or PW6 hardware acceptance is claimed here.
