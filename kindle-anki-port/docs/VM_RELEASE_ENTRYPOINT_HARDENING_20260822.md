# VM release-entrypoint ordering hardening — 2026-08-22

## Scope

This audit followed the package/QEMU provenance change documented in `docs/VM_PACKAGE_QEMU_BINDING_20260822.md`.

That production change made `package-and-audit.sh` correctly require fresh exact-rootfs QEMU evidence. A follow-on audit then checked every maintained release entrypoint for compatibility with the stricter production contract.

## Defects found

Three maintained entrypoints still encoded the old ordering.

### Top-level `Makefile`

The `package` target passed `PROJECT`, `ARMHF`, `VERSION`, and `BUILD_COMMIT`, but not the newly mandatory `QEMU` directory. After the production package hardening, `make package` would therefore fail immediately rather than exercise the intended release chain.

More importantly, the Makefile did not make the exact-rootfs QEMU output an explicit package input, leaving the public interface weaker than the underlying production script.

### Canonical GitHub Actions workflow

`.github/workflows/kindle-anki-port.yml` still ran `package-and-audit.sh` immediately after ARMHF build and only the generic QEMU ARM host-sanity test. GitHub does not contain the private checksum-matching PW6 5.19.6 rootfs, so this workflow cannot truthfully satisfy the exact-rootfs QEMU release gate.

Once the production script required `QEMU`, the old workflow was both operationally stale and semantically wrong: it still described a final-looking package stage where the required runtime input did not exist.

### `testenv/scripts/vm-advance.py`

The durable VM orchestration driver contained the most serious ordering defect. It invoked `package-and-audit.sh` before its optional `qemu-exact-rootfs` step. When no `--rootfs` was supplied, it could still construct a final-looking package checkpoint.

That contradicted the current completion rule and would have undermined the new fail-closed package/QEMU policy at the orchestration layer.

## Corrections

### Makefile release interface

`Makefile` now defines:

```text
QEMU ?= $(PROJECT_ROOT)/$(BUILD)/qemu
```

`make qemu-smoke` writes to that exact directory and passes `BUILD_COMMIT` through to the QEMU gate.

`make package` now requires the QEMU directory and invokes:

```text
PROJECT=...
ARMHF=...
QEMU=...
VERSION=...
BUILD_COMMIT=...
package-and-audit.sh
```

Current blob:

```text
Makefile  cd6c77d55f3f1cda1f5edcaeeaf3a854e1d1ec68
```

### Public CI is now explicitly a checkpoint, not a release builder

The workflow is renamed `Kindle Anki Port build checkpoint`.

It still performs public-source static, official Anki host, ARMHF and generic ARM QEMU sanity work when Actions capacity is available. It no longer invokes exact-rootfs QEMU or `package-and-audit.sh`, because the proprietary PW6 rootfs bytes are deliberately absent from GitHub.

Instead it persists host/ARMHF reports and a source archive with a mandatory `NOT-A-RELEASE.txt` explaining that the final installer is intentionally absent until exact-rootfs QEMU is run privately for the exact ARMHF bytes.

Current workflow blob:

```text
.github/workflows/kindle-anki-port.yml  a3f80ec5b598c4a8de43e68d85b31fcc6622eaba
```

This prevents a CI artifact from being mistaken for a finished PW6 release merely because the public build portion succeeded.

### VM driver release ordering

`vm-advance.py` schema is advanced to `3` and now encodes the full non-hardware release chain.

After ARMHF:

- if `--rootfs` is absent, the driver returns `armhf-checkpoint-passed`, records exact-rootfs QEMU and final package as missing, and does not create the installer;
- if a verified rootfs is present, the driver runs `qemu-exact-rootfs` before any package construction and records the resulting `QEMU-PROVENANCE.txt` SHA-256;
- if fewer than five unique real APKGs were exercised, or no typed-answer APKG was supplied, it returns `qemu-checkpoint-passed` and still withholds the installer;
- only when semantic/APKG, ARMHF and exact-rootfs QEMU gates are all present does it invoke `package-and-audit.sh`, passing `QEMU=<work>/qemu-exact-rootfs`;
- only that path can produce `non-hardware-release-gates-passed`.

Current blob:

```text
testenv/scripts/vm-advance.py  0bce7c09adf5d65df33bd4f48163dcb645224b48
```

### Contract tests

`tests/test_build_entrypoints.py` now requires the Makefile QEMU wiring and asserts that public CI emits the explicit non-release checkpoint instead of invoking the production package script.

`tests/test_vm_advance_contract.py` now checks the exact source ordering of the `qemu-exact-rootfs` gate before `package-audit`, the rootfs-absent ARMHF checkpoint, the semantic/APKG guard before package construction, and QEMU evidence handoff to the package script.

Current blobs:

```text
tests/test_build_entrypoints.py    3d827b50e280d3cfc2b78e4c1880d8e79513f90f
tests/test_vm_advance_contract.py  3c52f8de67cbbc267ab59fd70a2d837b6adb39d3
```

Both tests were already listed in `run-static-gates.sh`; no additional gate registration was required.

### Runbook alignment

`VM_RUNBOOK.md` was rewritten to remove the obsolete statement that the semantic bridge was the immediate blocker and to enforce the current sequence:

```text
clean source
-> static
-> official Anki + five APKGs
-> ARMHF/ABI
-> exact PW6 rootfs QEMU
-> QEMU-bound package
-> durable GitHub release evidence
```

Current blob:

```text
VM_RUNBOOK.md  b00d067e33245ab971c46378d6a81760a0225202
```

## Validation status

A full static/build rerun is **not** claimed in this continuation. The direct execution container still cannot resolve `github.com` for a normal clone/fetch, so the latest full source tree cannot be materialized there through Git. The checksum-matching private PW6 rootfs is also not mounted.

The current GitHub Actions run for head `68d0541d5ff2653f393bdbfe0ac8e451db817fea` was observed as failed before any recorded workflow step. Run `32531916780`, job `96925457873`, had zero returned steps and no downloadable job log (`BlobNotFound`). This is consistent with the repository's exhausted Actions capacity and is not counted as either a green validation result or evidence of a code-level test failure.

The source-level release-ordering audit is persisted at:

```text
docs/logs/KAP_RELEASE_ENTRYPOINT_AUDIT_20260822.log
```

No synthetic or historical result is promoted to a current-head full build.

## Material commits

```text
ab00d8a6710461829819b9bdb03606a0d52968b9  fix: wire QEMU evidence through release entrypoints
30a8ed295ecf81492f953a5162e666f4d6f464f1  ci: stop packaging without exact PW6 QEMU evidence
237d1c04e486a3a3bec779f9f1c6b87f8cefc3ea  test: enforce QEMU-bound release entrypoints
43633fbc5076e3401d35e71bd728675e4cf0119b  fix: order VM packaging after exact-rootfs QEMU
c168918570f47bfae02c6b351b5dd0a3f3659b41  test: enforce VM QEMU-before-package ordering
a4b099e8ace75e25500a3d9f09a0b204d7337e64  docs: align VM runbook with QEMU-bound packaging
8319598862597395aca0acd2fb995739bd5d8149  fix: withhold installer until semantic and QEMU gates pass
3e4cfec16ec31f93d076f9d36ac58c78688ac834  test: withhold VM installer until all semantic gates pass
68d0541d5ff2653f393bdbfe0ac8e451db817fea  test: assert exact VM release-gate ordering
dc56fd33fc80a474deb473da7bf67c33bd9d0355  test: persist release entrypoint audit evidence
```

## Release implication

The old package checkpoint SHA-256

```text
9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

remains stale. The maintained Makefile, VM driver, package script and public CI policy now agree that a final-looking installer must not be emitted before the exact PW6 rootfs QEMU gate is green for the same ARMHF bytes.

## Next actions

1. Materialize the then-current branch head in a build VM with working GitHub access and the pinned Anki/Cargo/KindleHF inputs.
2. Run the complete static gate, including the updated build-entrypoint and VM-driver contracts.
3. Rerun official Anki backend tests, the five real APKG integrations, ARMHF build and ABI/GLIBC audits from that same clean head.
4. Supply the checksum-matching private PW6 5.19.6 rootfs and run exact-rootfs QEMU against those fresh ARMHF outputs.
5. Only then allow the VM driver/package script to create the final ZIP, and persist the ZIP, SHA-256, contents, manifests and all provenance/test reports durably on GitHub.
6. Keep physical PW6 acceptance separate.
