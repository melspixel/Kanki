# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki semantic backend; no Ranki/rewrite/preload runtime |
| Ordinary GitHub source | complete | maintained source under `kindle-anki-port/` |
| Official Anki semantic bridge | green historical checkpoint | prior full `rslib`: `539 passed; 0 failed`; final clean-head rerun required |
| Five real APKG integration | green historical checkpoint | C-ABI reviewer lifecycle passed; typed-answer/AV observed; final clean-head rerun required |
| Reviewer/native host | deterministic fixtures green | host C/JS/runtime/lifecycle coverage persisted |
| Sync/collection ownership | hardened | wrapper-death/zombie-owner races reproduced and fixed |
| Host/ARMHF source provenance | hardened | clean project HEAD + exact pinned Anki HEAD enforced before build |
| ARMHF/ABI/GLIBC | green historical checkpoint | ARM hard-float outputs under target GLIBC ceiling; final clean-head rerun required |
| PW6 rootfs identity/preparation | pinned + fixture-green | exact firmware/rootfs/runtime hashes committed; private bytes not currently mounted |
| Exact-rootfs QEMU provenance | hardened | source/Anki/manifest/ARMHF identity bound; private paths removed from provenance |
| Package privacy/provenance | hardened | packaging requires matching exact-rootfs QEMU evidence and exact tested ARMHF hashes |
| Release entrypoints | hardened | Makefile/VM driver/public CI now prevent package-before-exact-QEMU |
| Test-policy docs | hardened | `TEST_ENVIRONMENT.md`, `testenv/README.md`, and `RELEASE_GATES.md` encode L1 -> L2 QEMU -> L2.5 package -> durable software artifacts -> separate HIL; static contract locks order |
| Public GitHub Actions | checkpoint-only | intentionally no final ZIP without private rootfs; current runs still fail before recorded steps |
| Final ZIP persistence | incomplete | old ZIP stale; fresh current-head QEMU-bound installer absent |
| PW6 hardware acceptance | not started | separate physical final gate after software-delivery hashes exist |

## Important historical checkpoints

```text
official Anki rslib: 539 passed; 0 failed
five real APKG C-ABI reviewer integrations: PASS
reviewer runtime fixture groups: 10 PASS
test_sync_worker: PASS
```

Historical ARMHF/ABI:

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc ceiling: GLIBC_2.35
```

These are regression checkpoints, not final release provenance.

## Lifecycle/source provenance

Targeted persisted lifecycle evidence:

```text
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Targeted build-source provenance suites:

```text
test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS
```

The build entrypoints now require the project `HEAD` to equal `BUILD_COMMIT`, the project subtree to be clean including untracked source, and the Anki checkout `HEAD` to equal `upstream.lock.json`.

## Exact PW6 runtime identity

```text
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
GLIBC ceiling             2.35
```

Canonical manifest: `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`.

The actual checksum-matching private PW6 rootfs is still absent from the current VM.

## QEMU-bound package gate

`run-qemu-smoke.sh` now proves the exact-rootfs run belongs to the same source commit, pinned Anki base, canonical manifest and ARMHF binary bytes. `QEMU-PROVENANCE.txt` contains stable hashes/identities rather than private absolute paths.

`package-and-audit.sh` now requires fresh QEMU evidence and rechecks:

```text
QEMU smoke PASS
PW6 rootfs verification PASS
backend/audio/sync smoke PASS
source commit identity
Anki commit identity
canonical rootfs-manifest SHA-256
SHA-256 of libanki-kindle.so, kap-app, kap-audio, kap-sync
```

Current blobs:

```text
testenv/scripts/run-qemu-smoke.sh       ac595dbeb6c411b51751953eef9b9400afe5a166
testenv/scripts/package-and-audit.sh    930a4128adf6e754f58a7f55da8014e59b90b122
tests/test_qemu_provenance.py           c3ccf143be655f2638770b5c5ea7f012d384c037
tests/test_package_reproducibility.py   9b85781c6a4738b117da5ff218276c373089aa55
```

Targeted isolated fixture evidence:

```text
matching ARMHF + QEMU provenance  rc=0
stale QEMU source_commit           rc=66
stale QEMU kap-app hash            rc=66
QEMU-SMOKE.txt = FAIL              rc=66
synthetic ZIP SHA-256
1d518583b1bae606885be4873bc3fa1528f826ac0ab77fd9453d8b676e5fa067
KAP_PACKAGE_QEMU_BINDING_20260822.log SHA-256
97fa62623ae4e940f8963b2bc3e15649306f413bbf441411dc950ca61af2e9be
```

The synthetic ZIP is not a product artifact.

## Release-entrypoint hardening

A follow-on audit found stale package ordering in the top-level Makefile, canonical GitHub Actions workflow, and `vm-advance.py`. They now agree with the production gate:

```text
static
-> official Anki backend
-> five real APKGs incl. typed-answer fixture
-> ARMHF/ABI
-> exact PW6 rootfs QEMU
-> package-and-audit
-> durable non-hardware release evidence
```

Current behavior:

```text
make package requires QEMU=<fresh run-qemu-smoke output>
public GitHub Actions emits NOT-A-RELEASE host/ARMHF checkpoint only
vm-advance without rootfs -> armhf-checkpoint-passed, no installer
vm-advance with incomplete required APKG coverage -> qemu-checkpoint-passed, no installer
vm-advance packages only after semantic + ARMHF + exact-rootfs QEMU gates
```

Current blobs:

```text
Makefile                                  cd6c77d55f3f1cda1f5edcaeeaf3a854e1d1ec68
.github/workflows/kindle-anki-port.yml   a3f80ec5b598c4a8de43e68d85b31fcc6622eaba
testenv/scripts/vm-advance.py            0bce7c09adf5d65df33bd4f48163dcb645224b48
tests/test_vm_advance_contract.py        3c52f8de67cbbc267ab59fd70a2d837b6adb39d3
VM_RUNBOOK.md                             b00d067e33245ab971c46378d6a81760a0225202
```

Detailed report: `docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md`.

## Release-policy documentation alignment

A further policy audit found `docs/RELEASE_GATES.md` still described a generic `Package` gate before any exact-rootfs QEMU gate and listed hardware acceptance in the same numbered release sequence. That contradicted the executable QEMU-before-package policy and the separate-HIL completion semantics.

It is now aligned with the other maintained policy surfaces:

```text
L0 host/static
-> L1 ARMHF/ABI
-> L2 exact PW6 rootfs QEMU
-> L2.5 package/privacy/reproducibility
-> durable GitHub software artifacts
-> separate physical PW6 HIL
```

`tests/test_build_entrypoints.py` now reads `docs/RELEASE_GATES.md` in addition to `docs/TEST_ENVIRONMENT.md` and `testenv/README.md`, and fails if the document stops requiring exact-rootfs QEMU before package construction or folds HIL back into software delivery.

Current release-policy blobs:

```text
docs/TEST_ENVIRONMENT.md          86bf0ce922844fcbb74c9af4996d7dbf61635e80
testenv/README.md                 979e45d878a3255f7ea429b17dec0dd36050f2d9
docs/RELEASE_GATES.md             6b40202cc35115270e72811933fe781b379f8fff
tests/test_build_entrypoints.py   009872702acab56cb1cd9ca62ce599f9d8352b6a
```

Targeted regression:

```text
old RELEASE_GATES contract: FAIL
new RELEASE_GATES contract: PASS
test_build_entrypoints.py py_compile: PASS
KAP_RELEASE_GATE_POLICY_20260822.log SHA-256
503bc75f03c1648ec7031eb7919f8a3cdf04a81f159234902a51b4134648218d
```

Commits:

```text
70e939954f193e7fb70dfb7c9be295156ad6393f
1baf30a181c6438c08770dce4a29ccc10e750ed0
5d99fbaf1d0679135001e32609fe90ee677c128d
61695cc717681c1de64b6bd212465fb7c76b5ae1
af58e6669dcc2bfc93fac975d746009530d58b54
```

Detailed report: `docs/VM_RELEASE_GATE_POLICY_HARDENING_20260822.md`.

## Current validation limitation

No fresh complete current-head build is claimed. The direct execution container still fails ordinary `git clone`/fetch because `github.com` DNS resolution is unavailable (`rc=128`), and the private PW6 rootfs is not mounted.

The canonical GitHub Actions run for code head `1baf30a181c6438c08770dce4a29ccc10e750ed0` failed before any recorded job step. Job `96929703461` exposed zero steps and no usable log blob; a rerun request was accepted, but no step-level result was available in this continuation. This is not counted as green and is not treated as a code regression result.

## Stale installer checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It cannot satisfy the current QEMU-bound release chain and remains stale.

## Current blockers / next actions

1. Materialize the latest clean branch head in a network-capable build VM with exact pinned Anki/Cargo/protoc/KindleHF inputs.
2. Run complete static gates, including release-entrypoint, VM-driver, QEMU/package and all three documentation-order contracts.
3. Run full official Anki backend plus five real APKG integrations from that same source identity.
4. Run ARMHF cross-build and ABI/GLIBC/export audit.
5. Supply the checksum-matching private PW6 rootfs and run exact-rootfs QEMU for those exact ARMHF bytes.
6. Run the QEMU-bound package gate and persist final ZIP/SHA-256/manifest/contents/all reports durably on GitHub.
7. Perform physical PW6 HIL separately after software-delivery hashes are recorded.

## Completion definition

**Not released.** Completion requires the full current-head source -> Anki -> APKG -> ARMHF -> exact-rootfs QEMU -> package -> durable GitHub evidence chain. Physical PW6 acceptance is a separate final result.
