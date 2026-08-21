# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical continuation point

- Repository: `melspixel/Kanki`
- Branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Official Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Ordinary-source materialization milestone: `0cf4716d8f66af96d38233ec5f723151787278d7`
- Latest source/test/doc checkpoint immediately before this handoff refresh: `b9d67eaab7b5ce22ed86f2b386f8b7506ed2ed0d`
- Always re-read branch HEAD before any build; this file update itself advances the branch.

Read next:

```text
PROGRESS.md
CODEX_COORDINATION.md
docs/TEST_ENVIRONMENT.md
VM_RUNBOOK.md
docs/VM_PACKAGE_QEMU_BINDING_20260822.md
docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md
```

## Product boundary

This is an independent Kindle port of desktop Anki, not a Ranki patch set.

- Official Anki `rslib` owns collection, scheduler, rendering semantics, typed answers, media, sync and undo.
- Kindle code exposes/consumes a named semantic C ABI and owns only platform concerns.
- Production contains no Ranki, `rewrite-v1`, `LD_PRELOAD`, deck-name branching or note-type-specific CSS hacks.
- PW6 hardware acceptance is separate from VM/QEMU acceptance.

## Completion rule

Do **not** mark software delivered until one coherent current-head provenance chain has all of the following persisted durably on GitHub:

1. complete ordinary maintainable source;
2. green complete static gates;
3. green official Anki 26.08.1 backend tests;
4. green five-real-APKG integration including typed-answer coverage;
5. green ARMv7 hard-float build plus ELF/ABI/GLIBC/export audit;
6. green exact checksum-matching PW6 5.19.6 rootfs QEMU smoke for the exact ARMHF bytes being released;
7. green privacy/package/reproducibility audit;
8. `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, package contents, ARMHF/QEMU/package provenance and complete test report.

Real PW6 HIL acceptance is recorded separately afterward and cannot be inferred from QEMU.

## Persisted historical green checkpoints

These results are useful regression evidence but **not** final current-head release provenance:

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

The old package checkpoint is stale:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It predates current lifecycle/build/QEMU/package provenance gates and must never be relabelled as final.

## Current lifecycle/source hardening

The maintained project has already closed these reproduced defects:

- sync wrapper death could make a live collection owner appear free;
- launcher/sync operation-lock ownership had signal/interruption windows;
- Linux state-`Z` zombies satisfy `kill -0`, causing stale owner refusal;
- PW6 firmware helper used a nonexistent manifest key, omitted MD5, had mode mismatch and community-mirror fallback;
- package policy missed some transient/user-state paths;
- host/ARMHF build provenance did not prove exact clean project/Anki source identities;
- exact-rootfs QEMU did not originally prove matching release source/ARMHF/manifest identity.

Current lifecycle evidence includes:

```text
test_zombie_operation_lock.sh  5/5 PASS
test_sync_wrapper_signal.sh    3/3 PASS
KAP_ZOMBIE_LOCK_20260822.log SHA-256
2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

Current source-provenance targeted evidence includes:

```text
test_armhf_provenance.py         6/6 PASS
test_host_backend_provenance.py  5/5 PASS
```

See the corresponding `docs/VM_*_20260822.md` reports for exact commands, commits and hashes.

## Exact PW6 runtime identity

Canonical manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned values:

```text
firmware:                  5.19.6 / 4832160042
firmware MD5:              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256:          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256:      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
/lib/ld-linux-armhf.so.3:  a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
/lib/libc.so.6:            5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK:                 6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max:         2.35
```

The exact checksum-matching firmware/rootfs bytes are private external build inputs and are not currently mounted in the execution VM. Oracle metadata is not accepted as a substitute.

## Latest package/QEMU release-chain hardening

### Production package gate

`testenv/scripts/package-and-audit.sh` now requires `QEMU=<fresh run-qemu-smoke output>` and fails closed unless all of the following match the release being archived:

```text
QEMU-SMOKE.txt == QEMU smoke: PASS
rootfs verification == PW6 rootfs verification: PASS
backend/audio/sync QEMU markers == PASS
QEMU source_commit == BUILD_COMMIT
QEMU anki_commit == upstream.lock.json commit
QEMU manifest SHA-256 == committed canonical PW6 manifest
QEMU hashes for libanki-kindle.so/kap-app/kap-audio/kap-sync == actual ARMHF files
```

It persists the QEMU/rootfs/backend/audio/sync reports and records rootfs-manifest plus QEMU-provenance hashes in `PACKAGE-PROVENANCE.txt`.

Current production blobs:

```text
testenv/scripts/package-and-audit.sh  930a4128adf6e754f58a7f55da8014e59b90b122
testenv/scripts/run-qemu-smoke.sh     ac595dbeb6c411b51751953eef9b9400afe5a166
```

`QEMU-PROVENANCE.txt` is path-sanitized: it records stable manifest/rootfs hashes, not private host absolute paths.

Targeted package/QEMU fixture evidence:

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

The synthetic ZIP is test evidence only.

## Latest release-entrypoint audit

After hardening the production package script, a follow-on audit found three stale callers that still encoded the old ordering:

1. top-level `Makefile` did not pass required QEMU evidence to packaging;
2. public GitHub Actions still attempted final package assembly despite having no private PW6 rootfs/exact-rootfs QEMU result;
3. `testenv/scripts/vm-advance.py` called package construction before its optional exact-rootfs QEMU step and could package when no rootfs was supplied.

All three are now corrected.

Current identities:

```text
Makefile                                    cd6c77d55f3f1cda1f5edcaeeaf3a854e1d1ec68
.github/workflows/kindle-anki-port.yml     a3f80ec5b598c4a8de43e68d85b31fcc6622eaba
testenv/scripts/vm-advance.py              0bce7c09adf5d65df33bd4f48163dcb645224b48
tests/test_build_entrypoints.py            3d827b50e280d3cfc2b78e4c1880d8e79513f90f
tests/test_vm_advance_contract.py          3c52f8de67cbbc267ab59fd70a2d837b6adb39d3
VM_RUNBOOK.md                               b00d067e33245ab971c46378d6a81760a0225202
```

Current behavior:

```text
make qemu-smoke -> writes the QEMU evidence directory used by make package
make package -> refuses absent QEMU directory
public GitHub Actions -> host/ARMHF checkpoint only + NOT-A-RELEASE.txt
vm-advance without rootfs -> armhf-checkpoint-passed, no installer
vm-advance with rootfs but incomplete real-APKG coverage -> qemu-checkpoint-passed, no installer
vm-advance with semantic + ARMHF + exact-rootfs QEMU green -> package-and-audit -> non-hardware-release-gates-passed
```

Detailed source-level audit:

```text
docs/VM_RELEASE_ENTRYPOINT_HARDENING_20260822.md
docs/logs/KAP_RELEASE_ENTRYPOINT_AUDIT_20260822.log
```

Material commits for this follow-on include:

```text
ab00d8a6710461829819b9bdb03606a0d52968b9  fix: wire QEMU evidence through release entrypoints
30a8ed295ecf81492f953a5162e666f4d6f464f1  ci: stop packaging without exact PW6 QEMU evidence
237d1c04e486a3a3bec779f9f1c6b87f8cefc3ea  test: enforce QEMU-bound release entrypoints
43633fbc5076e3401d35e71bd728675e4cf0119b  fix: order VM packaging after exact-rootfs QEMU
a4b099e8ace75e25500a3d9f09a0b204d7337e64  docs: align VM runbook with QEMU-bound packaging
8319598862597395aca0acd2fb995739bd5d8149  fix: withhold installer until semantic and QEMU gates pass
68d0541d5ff2653f393bdbfe0ac8e451db817fea  test: assert exact VM release-gate ordering
dc56fd33fc80a474deb473da7bf67c33bd9d0355  test: persist release entrypoint audit evidence
b9d67eaab7b5ce22ed86f2b386f8b7506ed2ed0d  docs: record release entrypoint ordering hardening
```

## Validation limitation in this continuation

The direct execution container still cannot perform a normal GitHub clone/fetch because `github.com` DNS resolution fails (`git clone` rc `128`). Consequently, no fresh **complete current-head** `run-static-gates.sh`, official Anki build, real APKG, or ARMHF build is claimed here.

A GitHub Actions run for checkpoint head `68d0541d5ff2653f393bdbfe0ac8e451db817fea` also completed as failure before any recorded job step; its job returned zero steps and no downloadable log. This is not treated as code-level failure evidence or as a green test.

Do not promote targeted source-contract checks or historical builds into current-head release provenance.

## Ordered next actions

1. Materialize the then-current clean branch head in a network-capable build VM with the exact pinned Anki checkout, prepared Cargo cache, protoc and KindleHF toolchain.
2. Run complete static gates, including the updated package/QEMU and release-entrypoint contract tests.
3. From the same clean source/Anki identity, run full official backend tests and the five real APKG integrations including typed-answer coverage.
4. Run ARMHF cross-build plus ELF/ABI/GLIBC/export audit.
5. Supply the checksum-matching private PW6 5.19.6 rootfs and run exact-rootfs QEMU against those exact fresh ARMHF outputs.
6. Only after all preceding gates are green, run `package-and-audit.sh` with the fresh QEMU evidence and persist the final ZIP/SHA-256/manifest/contents/full reports on GitHub.
7. Then begin separate physical PW6 HIL acceptance.

## Local/Codex boundary

Ordinary compilation remains VM-owned. The local host is not a compiler requirement. `CODEX_COORDINATION.md` Task B may be used only to transport the checksum-verified private PW6 rootfs into the VM/private channel; QEMU execution and packaging remain VM-owned.

## Release record

**Not released.**

Current release blockers are the full clean-head rerun, exact private PW6 rootfs QEMU, fresh QEMU-bound final package persistence, and separate real-PW6 HIL acceptance.
