# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Current evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki semantic backend; no Ranki/rewrite/preload runtime |
| Ordinary GitHub source | complete | maintained source is materialized under `kindle-anki-port/` |
| Official Anki semantic bridge | green checkpoint | prior full `rslib` run: `539 passed; 0 failed`; final clean-head rerun required |
| Five real APKG integration | green checkpoint | reviewer lifecycle exercised; typed-answer/AV observed; final clean-head rerun required |
| Native host/reviewer | deterministic fixtures green | host C/JS/runtime/lifecycle coverage persisted |
| Sync/collection ownership | hardened | wrapper-death and zombie-owner races reproduced/fixed; targeted regressions green |
| Host/ARMHF source provenance | hardened | project HEAD/cleanliness + exact Anki HEAD enforced before build |
| ARMHF build | green historical checkpoint | ARM EABI5 hard-float outputs exist historically; final clean-head rebuild required |
| ABI/GLIBC | green historical checkpoint | workers max GLIBC_2.4; backend max GLIBC_2.18; PW6 oracle ceiling 2.35 |
| PW6 rootfs identity/preparation | pinned + fixture-green | firmware/rootfs/runtime hashes committed; private exact bytes not currently mounted |
| Exact-rootfs QEMU provenance | hardened | rejects stale source/Anki/manifest/ARMHF identity; provenance path-sanitized |
| Package privacy/provenance | hardened | package requires matching exact-rootfs QEMU evidence and exact tested ARMHF hashes |
| Release entrypoints | hardened | Makefile/VM driver/public CI now enforce QEMU-before-package and no final ZIP without all gates |
| Public GitHub Actions | checkpoint-only | intentionally no final package because private rootfs is absent; Actions capacity currently unavailable |
| Final ZIP persistence | incomplete | old ZIP is stale; fresh QEMU-bound ZIP not yet produced |
| PW6 hardware acceptance | not started | real-device HIL remains separate final gate |

## Persisted key checkpoints

Official backend historical checkpoint:

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

Five real APKG C-ABI integrations previously passed open/deck/queue/question/reveal/rate/close. The Advanced Vocabulary fixture exercised typed-answer behavior; AV packets were observed in multiple fixtures.

Historical ARMHF/ABI checkpoint:

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc ceiling: GLIBC_2.35
```

These are regression checkpoints only and must be regenerated from the eventual release head.

## Lifecycle and source-provenance hardening

Reproduced lifecycle defects included wrapper death leaving the real sync worker alive, interruption windows around operation-lock ownership, and stale lock owners that were actually unreaped Linux zombies. The current launch/sync liveness predicate treats `/proc/<pid>/stat` state `Z` as dead while retaining the prior `kill -0` fallback where `/proc` is unavailable.

Targeted evidence:

```text
test_zombie_operation_lock.sh   5/5 PASS
test_sync_wrapper_signal.sh     3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Host-backend and ARMHF build entrypoints now require:

```text
PROJECT HEAD == BUILD_COMMIT
PROJECT subtree clean including untracked source
ANKI HEAD == upstream.lock.json pin
ARMHF ANKI_COMMIT override, if present, == lock-file pin
```

Targeted provenance suites previously passed:

```text
test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS
```

## Exact PW6 5.19.6 rootfs

Canonical manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned hashes:

```text
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
GLIBC ceiling             2.35
```

The canonical Python and shell preparation helpers verify the pinned firmware SHA-256/MD5, rootfs image hash and required runtime files. Automatic shell-helper download is restricted to official Amazon sources. The actual private checksum-matching firmware/rootfs bytes are not currently mounted in the VM.

## QEMU/package release binding

`run-qemu-smoke.sh` now binds exact-rootfs evidence to:

```text
clean project BUILD_COMMIT
pinned Anki commit
ARMHF-GATES.txt == PASS
matching ARMHF BUILD-PROVENANCE.txt
canonical PW6 5.19.6 manifest bytes
```

`QEMU-PROVENANCE.txt` records stable identities/hashes and omits private absolute rootfs paths.

`package-and-audit.sh` now requires `QEMU=<fresh exact-rootfs output>` and verifies:

```text
QEMU smoke PASS
rootfs verification PASS
backend/audio/sync smoke PASS
same source commit
same Anki commit
same canonical rootfs-manifest SHA-256
same SHA-256 for libanki-kindle.so, kap-app, kap-audio, kap-sync
```

Successful packaging persists QEMU/rootfs reports and hashes their provenance into `PACKAGE-PROVENANCE.txt`.

Targeted isolated package/QEMU fixture evidence:

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

The synthetic ZIP is not a release artifact.

Current blobs:

```text
testenv/scripts/package-and-audit.sh  930a4128adf6e754f58a7f55da8014e59b90b122
testenv/scripts/run-qemu-smoke.sh     ac595dbeb6c411b51751953eef9b9400afe5a166
tests/test_package_reproducibility.py 9b85781c6a4738b117da5ff218276c373089aa55
tests/test_qemu_provenance.py         c3ccf143be655f2638770b5c5ea7f012d384c037
```

Detailed report: `docs/VM_PACKAGE_QEMU_BINDING_20260822.md`.

## Release-entrypoint follow-on audit

After the production package contract changed, three maintained callers were discovered to be stale:

- `Makefile` package target did not pass QEMU evidence;
- public GitHub Actions still attempted package construction without private exact-rootfs bytes;
- `vm-advance.py` invoked packaging before its optional exact-rootfs QEMU step and could emit an installer without a rootfs.

The current ordering is now enforced end to end:

```text
static
-> official Anki backend
-> five real APKGs incl. typed-answer fixture
-> ARMHF/ABI
-> exact-rootfs QEMU
-> package-and-audit
-> non-hardware release PASS
```

Behavioral contracts:

```text
make package: requires QEMU=<fresh run-qemu-smoke output>
public CI: host/ARMHF checkpoint only, contains NOT-A-RELEASE.txt and no final ZIP
vm-advance without rootfs: armhf-checkpoint-passed, no installer
vm-advance with rootfs but incomplete APKG coverage: qemu-checkpoint-passed, no installer
vm-advance with all semantic/ARMHF/QEMU gates: package allowed
```

Current blobs:

```text
Makefile                                  cd6c77d55f3f1cda1f5edcaeeaf3a854e1d1ec68
.github/workflows/kindle-anki-port.yml   a3f80ec5b598c4a8de43e68d85b31fcc6622eaba
testenv/scripts/vm-advance.py            0bce7c09adf5d65df33bd4f48163dcb645224b48
tests/test_build_entrypoints.py          3d827b50e280d3cfc2b78e4c1880d8e79513f90f
tests/test_vm_advance_contract.py        3c52f8de67cbbc267ab59fd70a2d837b6adb39d3
VM_RUNBOOK.md                             b00d067e33245ab971c46378d6a81760a0225202
```

Detailed report/log:

```text
docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md
docs/logs/KAP_RELEASE_ENTRYPOINT_AUDIT_20260822.log
```

Material commits through the report checkpoint:

```text
ab00d8a6710461829819b9bdb03606a0d52968b9
30a8ed295ecf81492f953a5162e666f4d6f464f1
237d1c04e486a3a3bec779f9f1c6b87f8cefc3ea
43633fbc5076e3401d35e71bd728675e4cf0119b
c168918570f47bfae02c6b351b5dd0a3f3659b41
a4b099e8ace75e25500a3d9f09a0b204d7337e64
8319598862597395aca0acd2fb995739bd5d8149
3e4cfec16ec31f93d076f9d36ac58c78688ac834
68d0541d5ff2653f393bdbfe0ac8e451db817fea
dc56fd33fc80a474deb473da7bf67c33bd9d0355
b9d67eaab7b5ce22ed86f2b386f8b7506ed2ed0d
```

## Validation status of the latest continuation

No full current-head build is claimed. The direct execution container still fails normal `git clone`/fetch because `github.com` DNS resolution is unavailable (`rc=128`), and the private exact PW6 rootfs is not mounted.

A GitHub Actions run at checkpoint `68d0541d5ff2653f393bdbfe0ac8e451db817fea` concluded failure before any recorded step; the job returned zero steps and no downloadable log. It is therefore not useful as either green validation or a code-level failure diagnosis.

All historical and synthetic evidence remains explicitly labelled as checkpoint/fixture evidence.

## Stale package checkpoint

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

This is **not** the final release and cannot satisfy the current QEMU-bound package gate.

## Current blockers

1. Complete reproducible static/backend/APKG/ARMHF rerun from the latest clean branch head.
2. Checksum-matching private PW6 5.19.6 rootfs bytes for exact-rootfs QEMU.
3. Fresh final installer generated only after exact-rootfs QEMU and persisted with SHA-256/manifests/contents/full reports.
4. Separate physical PW6 HIL acceptance after non-hardware release artifacts are final.

## Ordered next actions

1. Materialize the then-current branch head in a network-capable VM with exact Anki/Cargo/protoc/KindleHF inputs.
2. Run complete static gates, including new release-entrypoint/QEMU package contracts.
3. Run full official Anki backend and five-real-APKG integrations from the same clean identity.
4. Run ARMHF cross-build and ABI/GLIBC/export audits.
5. Supply verified private PW6 rootfs and run exact-rootfs QEMU for those exact ARMHF outputs.
6. Run QEMU-bound package audit and persist final ZIP/SHA-256/manifest/contents/provenance/test reports on GitHub.
7. Perform and record real-PW6 acceptance separately.

## Completion definition

The port remains **not released**. Do not mark complete until the full current-head source -> Anki pin -> semantic/APKG -> ARMHF -> exact PW6 rootfs QEMU -> package -> durable GitHub evidence chain is green. Hardware acceptance remains an independent final gate.
