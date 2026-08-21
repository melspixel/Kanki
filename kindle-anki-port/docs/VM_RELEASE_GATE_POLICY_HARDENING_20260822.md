# VM release-gate policy hardening — 2026-08-22

## Scope

This continuation started from branch head `97ee84d3596baf456d0dadacafa1443dffdee253` after reading `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md` as required.

The goal of this pass was to keep the maintained release policy consistent with the already fail-closed executable release chain while the build VM remains unable to clone GitHub normally and the private PW6 5.19.6 rootfs is not mounted.

## Defect found

`docs/RELEASE_GATES.md` had drifted behind the maintained production policy. Its old numbered list jumped from generic host/ARMHF checks directly to `Package`, with no exact-rootfs QEMU gate, and then listed `Hardware acceptance` in the same release-gate sequence.

That was inconsistent with the maintained invariant already encoded by `docs/TEST_ENVIRONMENT.md`, `testenv/README.md`, the top-level Makefile, `run-qemu-smoke.sh`, `package-and-audit.sh`, `vm-advance.py`, and public CI:

```text
L0 host/static/official Anki semantics
-> five real APKG integrations
-> L1 ARMHF/ABI/GLIBC
-> L2 exact checksum-matching PW6 rootfs QEMU for those exact ARMHF bytes
-> L2.5 QEMU-bound package/privacy/reproducibility audit
-> durable GitHub software-release artifacts
-> separate physical PW6 HIL result
```

The stale release-gate document could therefore encourage two incorrect interpretations:

1. package construction was permissible after host/ARMHF checks without exact-rootfs QEMU; or
2. software delivery and physical PW6 acceptance were one inseparable completion state instead of distinct results.

`tests/test_build_entrypoints.py` did not read `docs/RELEASE_GATES.md`, so the drift was not protected by static gates.

## Fix

`docs/RELEASE_GATES.md` now explicitly requires one coherent current-head provenance chain and orders the non-hardware software gates as:

```text
source/upstream identity
-> L0 host semantics/static
-> five real APKG integrations incl. typed answer
-> L1 ARMHF/ABI
-> L2 exact-rootfs QEMU
-> L2.5 package/privacy/reproducibility
-> durable final ZIP/SHA-256/manifest/contents/reports
```

It also states that a final-looking `Kindle-Anki-Port-PW6-armhf.zip` must not be assembled before L2 passes for the exact ARMHF bytes to be archived, and moves physical PW6 HIL into a separate section that starts only after software-release hashes are recorded.

`tests/test_build_entrypoints.py` now reads `docs/RELEASE_GATES.md` and requires:

```text
5. L1 ARMHF/ABI:
6. L2 exact-rootfs QEMU:
7. L2.5 package/privacy/reproducibility:
only after L2 PASS
must not be assembled before the exact-rootfs L2 gate passes
## Hardware acceptance — separate from software delivery
Hardware acceptance is recorded as a distinct physical-device result
```

It also enforces the document order `L1 -> L2 -> L2.5 -> separate HIL`.

Because `run-static-gates.sh` already invokes `tests/test_build_entrypoints.py`, this policy is now part of the maintained static contract.

## Commits

```text
70e939954f193e7fb70dfb7c9be295156ad6393f  docs: align release gates with exact-rootfs QEMU policy
1baf30a181c6438c08770dce4a29ccc10e750ed0  test: lock release-gate QEMU and HIL ordering
5d99fbaf1d0679135001e32609fe90ee677c128d  test: persist release-gate policy regression evidence
```

GitHub content blobs after the code/doc updates:

```text
docs/RELEASE_GATES.md           6b40202cc35115270e72811933fe781b379f8fff
tests/test_build_entrypoints.py 009872702acab56cb1cd9ca62ce599f9d8352b6a
```

## Targeted validation

The execution container still cannot materialize the complete repository with ordinary Git because DNS resolution for `github.com` fails. The exact attempted command was:

```sh
rm -rf /tmp/Kanki-auto1
git clone --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki-auto1
```

Result:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

Therefore no fresh complete static/backend/ARMHF build is claimed in this pass.

A targeted isolated regression was run against the exact old release-gate text and the replacement text. The validator applies the same new policy markers/order that were added to `test_build_entrypoints.py`. `test_build_entrypoints.py` was also syntax-checked with `python3 -m py_compile`.

Exact targeted commands:

```sh
python3 -m py_compile /tmp/kanki-policy/tests/test_build_entrypoints.py
python3 <targeted release-gate contract validator>
sha256sum \
  /tmp/kanki-policy/docs/RELEASE_GATES.md \
  /tmp/kanki-policy/tests/test_build_entrypoints.py \
  /tmp/kanki-policy/logs/KAP_RELEASE_GATE_POLICY_20260822.log
```

Result:

```text
old_release_gates_contract=FAIL
new_release_gates_contract=PASS
test_build_entrypoints_py_compile=PASS
```

Persisted log:

```text
docs/logs/KAP_RELEASE_GATE_POLICY_20260822.log
SHA-256 503bc75f03c1648ec7031eb7919f8a3cdf04a81f159234902a51b4134648218d
```

Local exact-file SHA-256 values used by that targeted validation:

```text
docs/RELEASE_GATES.md
  cefb73a2a6999ae1ea5373a07d12e0c021cc465fb1f08d64a3a9eda7b1391928
tests/test_build_entrypoints.py
  cf983f6a82458a1b96f1281fa317e49880b85011cc86c13c7299611885ebf07b
```

These SHA-256 values are byte hashes, not Git blob IDs.

## GitHub Actions observation

The push at code head `1baf30a181c6438c08770dce4a29ccc10e750ed0` created canonical workflow run `32533386741`. Its first job `96929703461` completed with `failure` before any recorded step and its log blob was unavailable (`404 BlobNotFound`).

A rerun was then requested successfully. The rerun created job `96929792919`, which also completed with `failure` and again exposed zero recorded steps. This reproduces the unavailable-runner/capacity symptom twice and still provides no test-level diagnostic. Neither attempt is counted as code validation.

## Release status

**Not released.** This pass closes documentation/test-policy drift only. It does not replace the required clean-head release rerun and does not provide the missing private PW6 rootfs.

The stale historical ZIP remains invalid as final release evidence:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Ordered next actions

1. Re-read the then-current branch head and required continuation files.
2. Re-attempt a normal clone/materialization in the build VM; if GitHub Actions begins yielding real steps, inspect and use those results as additional checkpoint evidence.
3. Run the complete static gate suite so the new `RELEASE_GATES.md` contract executes with the rest of the repository.
4. From the same clean identity, rerun official Anki 26.08.1 backend tests and all five real APKG integrations.
5. Rebuild ARMHF and rerun ELF/ABI/GLIBC/export audit.
6. Supply the checksum-matching private PW6 5.19.6 rootfs, then run exact-rootfs QEMU on those exact ARMHF bytes.
7. Only after L2 PASS, run the QEMU-bound package gate and persist the final ZIP/SHA-256/manifest/contents/full reports.
8. Record physical PW6 HIL separately after software delivery hashes exist.
