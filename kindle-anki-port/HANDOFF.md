# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical continuation point

- Repository: `melspixel/Kanki`
- Branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Official Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Always read the live branch HEAD before building; documentation updates advance HEAD too.

Read in this order before continuing:

```text
HANDOFF.md
PROGRESS.md
CODEX_COORDINATION.md
docs/TEST_ENVIRONMENT.md
VM_RUNBOOK.md
```

Latest detailed reports:

```text
docs/VM_RELEASE_GATE_POLICY_HARDENING_20260822.md
docs/VM_PACKAGE_QEMU_BINDING_20260822.md
docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md
docs/logs/KAP_RELEASE_GATE_POLICY_20260822.log
docs/logs/KAP_RELEASE_ENTRYPOINT_AUDIT_20260822.log
docs/logs/KAP_RELEASE_POLICY_DOC_ALIGNMENT_20260822.log
```

## Product boundary

This is an independent Kindle port of desktop Anki, not a Ranki/rewrite patch set. Official Anki `rslib` owns collection, scheduler, renderer semantics, typed answers, media, sync and undo. Kindle code owns platform integration only. Production contains no Ranki, `rewrite-v1`, `LD_PRELOAD`, deck-name routing or note-type-specific CSS patches.

PW6 hardware acceptance is a separate final gate and can never be inferred from VM/QEMU evidence.

## Completion rule

Do **not** mark software delivered until one coherent current-head provenance chain is green and durably persisted:

```text
complete ordinary source
-> complete static gates
-> official Anki 26.08.1 backend tests
-> five real APKG integrations including typed-answer coverage
-> ARMv7 hard-float build + ELF/ABI/GLIBC/export audit
-> exact checksum-matching PW6 5.19.6 rootfs QEMU for those exact ARMHF bytes
-> QEMU-bound package/privacy/reproducibility audit
-> final ZIP + SHA-256 + internal manifest + contents + complete reports on GitHub
```

Only after that may physical PW6 HIL begin, and its result is recorded separately.

## Historical green checkpoints — not final release provenance

```text
official Anki rslib: 539 passed; 0 failed
five real APKG C-ABI reviewer integrations: PASS
reviewer runtime fixture groups: 10 PASS
test_sync_worker: PASS
ARMHF checkpoint:
  kap-app           ARM EABI5 hard-float, GLIBC_2.4
  kap-audio         ARM EABI5 hard-float, GLIBC_2.4
  kap-sync          ARM EABI5 hard-float, GLIBC_2.4
  libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc oracle ceiling: GLIBC_2.35
```

These predate the newest release-provenance changes and must be rerun from the eventual release head.

The old ZIP remains explicitly stale:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

Never publish or relabel it as final.

## Lifecycle/source hardening already persisted

Resolved reproduced defects include wrapper-death collection ownership, operation-lock signal windows, stale state-`Z` zombie owners, PW6 helper manifest/hash/source errors, package transient-state leakage, and host/ARMHF source-identity gaps.

Targeted lifecycle evidence:

```text
test_zombie_operation_lock.sh  5/5 PASS
test_sync_wrapper_signal.sh    3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Targeted source-provenance evidence:

```text
test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS
```

See the corresponding `docs/VM_*_20260822.md` reports for exact commands and commits.

## Exact PW6 5.19.6 runtime identity

Canonical manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned values:

```text
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max          2.35
```

The actual checksum-matching firmware/rootfs bytes are private external inputs and are not currently mounted in the execution VM. Hash/oracle metadata alone is not accepted as a runtime test.

## QEMU/package release binding

`run-qemu-smoke.sh` now binds exact-rootfs PASS evidence to the clean project commit, pinned Anki commit, canonical PW6 manifest bytes and exact ARMHF binary hashes. Persisted `QEMU-PROVENANCE.txt` is path-sanitized and does not leak private absolute rootfs paths.

`package-and-audit.sh` now requires `QEMU=<fresh run-qemu-smoke output>` and independently checks:

```text
QEMU-SMOKE.txt == QEMU smoke: PASS
PW6 rootfs verification == PASS
backend/audio/sync smoke markers == PASS
QEMU source_commit == package BUILD_COMMIT
QEMU anki_commit == upstream.lock.json pin
QEMU manifest SHA-256 == committed canonical PW6 manifest
QEMU hashes for libanki-kindle.so/kap-app/kap-audio/kap-sync == actual ARMHF files
```

Successful packaging persists QEMU/rootfs/backend/audio/sync evidence and records rootfs-manifest/QEMU-provenance hashes in `PACKAGE-PROVENANCE.txt`.

Current production blobs:

```text
testenv/scripts/package-and-audit.sh  930a4128adf6e754f58a7f55da8014e59b90b122
testenv/scripts/run-qemu-smoke.sh     ac595dbeb6c411b51751953eef9b9400afe5a166
tests/test_package_reproducibility.py 9b85781c6a4738b117da5ff218276c373089aa55
tests/test_qemu_provenance.py         c3ccf143be655f2638770b5c5ea7f012d384c037
```

Targeted isolated evidence:

```text
matching ARMHF + QEMU provenance  rc=0
stale QEMU source_commit           rc=66
stale tested kap-app hash          rc=66
QEMU-SMOKE.txt = FAIL              rc=66
synthetic ZIP SHA-256
1d518583b1bae606885be4873bc3fa1528f826ac0ab77fd9453d8b676e5fa067
KAP_PACKAGE_QEMU_BINDING_20260822.log SHA-256
97fa62623ae4e940f8963b2bc3e15649306f413bbf441411dc950ca61af2e9be
```

The synthetic ZIP is fixture evidence only.

## Release-entrypoint hardening

A follow-on audit found three maintained callers still using the obsolete package-before-exact-QEMU flow:

- top-level `Makefile` did not pass QEMU evidence;
- public GitHub Actions attempted package construction despite no private PW6 rootfs;
- `vm-advance.py` packaged before its optional exact-rootfs QEMU step and could emit an installer without a rootfs.

These are fixed. Current behavior is:

```text
make qemu-smoke -> writes evidence to $(QEMU)
make package -> requires $(QEMU)
public CI -> host/ARMHF checkpoint only + NOT-A-RELEASE.txt, no final ZIP
vm-advance without rootfs -> armhf-checkpoint-passed, no installer
vm-advance with rootfs but incomplete required real-APKG coverage -> qemu-checkpoint-passed, no installer
vm-advance with semantic + ARMHF + exact-rootfs QEMU green -> package allowed
```

Current blobs:

```text
Makefile                                  cd6c77d55f3f1cda1f5edcaeeaf3a854e1d1ec68
.github/workflows/kindle-anki-port.yml   a3f80ec5b598c4a8de43e68d85b31fcc6622eaba
testenv/scripts/vm-advance.py            0bce7c09adf5d65df33bd4f48163dcb645224b48
tests/test_vm_advance_contract.py        3c52f8de67cbbc267ab59fd70a2d837b6adb39d3
VM_RUNBOOK.md                             b00d067e33245ab971c46378d6a81760a0225202
```

## Test-policy documentation drift found and fixed

The release policy is now aligned across `docs/TEST_ENVIRONMENT.md`, `testenv/README.md`, and `docs/RELEASE_GATES.md`:

```text
L0 host/static
-> L1 ARMHF/ABI
-> L2 exact PW6 rootfs QEMU
-> L2.5 package/privacy/reproducibility
-> durable artifacts
-> separate L5 PW6 HIL
```

`tests/test_build_entrypoints.py` reads all three policy surfaces and fails static gates if package ordering drifts ahead of exact-rootfs QEMU or if `RELEASE_GATES.md` folds HIL back into the software-delivery chain.

Current release-policy blobs:

```text
docs/TEST_ENVIRONMENT.md          86bf0ce922844fcbb74c9af4996d7dbf61635e80
testenv/README.md                 979e45d878a3255f7ea429b17dec0dd36050f2d9
docs/RELEASE_GATES.md             6b40202cc35115270e72811933fe781b379f8fff
tests/test_build_entrypoints.py   009872702acab56cb1cd9ca62ce599f9d8352b6a
```

Newest targeted regression evidence:

```text
old RELEASE_GATES contract: FAIL
new RELEASE_GATES contract: PASS
test_build_entrypoints.py py_compile: PASS
KAP_RELEASE_GATE_POLICY_20260822.log SHA-256
503bc75f03c1648ec7031eb7919f8a3cdf04a81f159234902a51b4134648218d
```

Detailed report: `docs/VM_RELEASE_GATE_POLICY_HARDENING_20260822.md`.

Newest commits:

```text
70e939954f193e7fb70dfb7c9be295156ad6393f  docs: align release gates with exact-rootfs QEMU policy
1baf30a181c6438c08770dce4a29ccc10e750ed0  test: lock release-gate QEMU and HIL ordering
5d99fbaf1d0679135001e32609fe90ee677c128d  test: persist release-gate policy regression evidence
61695cc717681c1de64b6bd212465fb7c76b5ae1  docs: record release-gate policy hardening
```

## Current validation limitation

No fresh **complete current-head** build is claimed. The direct execution container still cannot perform a normal GitHub clone/fetch because `github.com` DNS resolution fails (`git clone` rc `128`). The private PW6 rootfs is also absent.

The canonical GitHub Actions run for code head `1baf30a181c6438c08770dce4a29ccc10e750ed0` failed before any recorded job step; job `96929703461` returned zero steps and no usable log blob. A rerun request was accepted, but no step-level result was available in this continuation. Treat this as unavailable Actions capacity, not as code validation.

Historical/synthetic evidence remains labelled as such and must not be promoted to final provenance.

## Ordered next actions

1. Materialize the then-current clean branch head in a network-capable build VM with exact pinned Anki, Cargo cache, protoc and KindleHF inputs.
2. Run complete static gates, including release-entrypoint, VM-driver, QEMU/package and all three documentation-order contracts.
3. From the same clean source/Anki identity, run full official backend tests and five real APKG integrations including typed-answer coverage.
4. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit.
5. Supply the checksum-matching private PW6 5.19.6 rootfs and run exact-rootfs QEMU against those exact fresh ARMHF outputs.
6. Only then run QEMU-bound package audit and persist final ZIP/SHA-256/manifest/contents/full reports on GitHub.
7. Begin separate physical PW6 HIL acceptance only after final non-hardware hashes are recorded.

## Local/Codex boundary

Ordinary compilation remains VM-owned. The local host is not a compiler requirement. `CODEX_COORDINATION.md` Task B may be used only to transport the verified private PW6 rootfs into the VM/private channel. QEMU execution and packaging remain VM-owned.

## Release record

**Not released.**

Current blockers are the full clean-head rerun, exact private PW6 rootfs QEMU, fresh QEMU-bound installer/report persistence, and separate real-PW6 HIL acceptance.
