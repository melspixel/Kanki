# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki semantic backend; no Ranki/rewrite/preload runtime |
| Ordinary GitHub source | complete | maintained source under `kindle-anki-port/` |
| Official Anki semantic bridge | hardened + green historical checkpoint | deterministic overlay now verified against pinned HEAD + clean project; prior full `rslib`: `539 passed; 0 failed`; final clean-head rerun required |
| Five real APKG integration | green historical checkpoint | C-ABI reviewer lifecycle passed; typed-answer/AV observed; final clean-head rerun required |
| Reviewer/native host | deterministic fixtures green historically | full current-head rerun pending |
| Sync/collection ownership | hardened | wrapper-death/zombie-owner races reproduced and fixed |
| Git source identity | hardened | host/ARMHF/QEMU require resolvable `HEAD^{commit}` + successful clean-status query; package requires real Git checkout |
| Anki working-tree provenance | hardened newest | injector requires exact deterministic overlay only; unrelated tracked/staged/untracked Anki changes rejected |
| Cargo build-state provenance | hardened newest | host/ARMHF force `$ANKI/target` and recreate it before Cargo; caller/stale target state not reused |
| Host/ARMHF source provenance | hardened | clean current project commit + exact resolvable pinned Anki commit + exact overlay required before build |
| ARMHF/ABI/GLIBC | green historical checkpoint | ARM hard-float outputs under target GLIBC ceiling; final clean-head rerun required |
| PW6 rootfs identity/preparation | hardened + private input pending | firmware/runtime hashes pinned; L2 requires both extracted tree and retained full image |
| Exact-rootfs QEMU provenance | hardened | QEMU executes only against a tree freshly `rdump`ed from verified retained image; stale rerun PASS invalidated |
| Package privacy/provenance | hardened | package requires exact-rootfs QEMU evidence and resolvable clean Git source bytes |
| Release entrypoints/orchestrator | hardened | Makefiles/VM driver/public CI prevent package-before-exact-QEMU; `--rootfs` requires `--rootfs-image` |
| Public GitHub Actions | checkpoint-only / infrastructure unavailable | previous observed checkpoint failed before any recorded step; not test evidence |
| Final ZIP persistence | incomplete | old ZIP stale; fresh current-head installer absent |
| PW6 hardware acceptance | not started | separate physical final result after software-delivery hashes exist |

## Historical checkpoints — not final provenance

```text
official Anki rslib: 539 passed; 0 failed
five real APKG C-ABI reviewer integrations: PASS
reviewer runtime fixture groups: 10 PASS
test_sync_worker: PASS
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc ceiling: GLIBC_2.35
```

These must be rerun from the eventual final clean source/Anki identity because the release-provenance contract is now stricter than when they were produced.

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

Canonical manifest: `testenv/qemu/pw6-5.19.6-rootfs-manifest.json`. The actual checksum-matching private extracted rootfs and retained rootfs image are still absent from the current VM.

## New deterministic Anki overlay hardening

The prior identity checks proved the Anki checkout `HEAD` was the exact 26.08.1 commit, but did not prove Cargo saw only that commit plus the maintained Kindle bridge. A dirty Anki working tree can keep the same HEAD.

The production path now enforces:

```text
pinned Anki HEAD^{commit}
+ clean kindle-anki-port project source
+ deterministic bridge transformation
= only allowed Anki working-tree delta
```

`tools/inject_into_anki.py` reads the three edited upstream files from pinned `HEAD`, reconstructs the exact expected modifications, byte-compares the two bridge source files and all transformed files, and requires the tracked/staged/untracked dirty set to equal exactly the overlay delta. Any unrelated modification fails closed.

`run-host-backend-gates.sh` uses that verifier before official Cargo tests/build. `run-armhf-gates.sh` independently reruns the same idempotent verification before cross-compilation instead of trusting the host-time working tree.

Both gates also force `CARGO_TARGET_DIR=$ANKI/target` and delete that directory before Cargo, preventing copied/caller-provided ignored build state from being reused.

Current blobs:

```text
tools/inject_into_anki.py                     b7cf140e742c219ca0fe7acc675a08fe075e9c17
testenv/scripts/run-host-backend-gates.sh     3e2e463385713d096efab5a1f3c5ba5b065941ec
testenv/scripts/run-armhf-gates.sh            197054ebfd84b6b24d7f5237a79149f4ad7ccacb
tests/test_armhf_provenance.py                bc8fcfddde7657ad2df3646d541a9963ef887707
tests/test_injector.py                        9f8da713f59cf46ecfb42a49402426ff7a1ab858
```

Targeted synthetic local-Git evidence:

```text
clean deterministic injection                       PASS
idempotent reinjection                              PASS
unrelated untracked source rejection                PASS
overlay-owned byte tamper rejection                 PASS
unrelated tracked source rejection                  PASS
unrelated staged source rejection                   PASS
gate-owned Cargo target recreation/isolation        PASS
7/7 PASS
```

Persisted log:

```text
docs/logs/KAP_ANKI_OVERLAY_TARGETED_20260822.log
SHA-256 d3240f300e6b5605ead549f780d93907abfd8b38005d8536ad2d1c3db79040e8
```

Detailed report: `docs/VM_ANKI_OVERLAY_PROVENANCE_HARDENING_20260822.md`.

## Image-derived exact-rootfs runtime binding

The L2 chain remains fail-closed:

```text
run-qemu-smoke.sh
  verifies supplied ROOTFS against the pinned runtime oracle
  verifies retained ROOTFS_IMAGE against the canonical image SHA-256
  invalidates prior QEMU PASS/provenance before new dynamic L2 work
  requires debugfs
  rdump's the verified image into a private temporary rootfs
  verifies that image-derived rootfs
  runs backend/audio/sync QEMU only with -L <image-derived-rootfs>
  records rootfs_input_verified=true
  records rootfs_verified=true
  records rootfs_runtime_source=verified-image-rdump

package-and-audit.sh
  requires both rootfs verification reports
  requires matching image-derived-runtime QEMU provenance
  rejects older caller-tree/image-hash-only evidence
```

Previous targeted QEMU fixture: 9/9 PASS. Log SHA-256 `985e150dbe7390582d8daad57d6cc0f244c296c60e0434d496e95b3e24f461ac`.

## Existing Git/source/lifecycle hardening

Production gates also require resolvable Git commit objects, explicit successful source-status checks, matching `BUILD_COMMIT`, and clean maintained project source. Packaging requires a real Git checkout unconditionally. Lifecycle tests reject stale zombie lock owners and protect wrapper-death/sync collection ownership.

Persisted targeted evidence includes:

```text
KAP_GIT_IDENTITY_TARGETED_20260822.log
SHA-256 649526115118aa93996b3e66f75fff77111e0d0abee506bff167cb6cc0da13d7

KAP_ZOMBIE_LOCK_20260822.log
SHA-256 2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

## Current validation limitation

No fresh complete current-head build is claimed. Ordinary network access in the execution container still fails DNS resolution. This run reconfirmed:

```text
git ls-remote https://github.com/melspixel/Kanki.git
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

The private checksum-matching PW6 rootfs tree/image pair is also absent. Historical/synthetic evidence must not be promoted to final provenance.

## Stale installer

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

It remains stale and must not be published as final.

## Current blockers / next actions

1. Resolve and materialize the live clean branch head with complete Git objects in a network-capable build VM with exact pinned Anki/Cargo/protoc/KindleHF inputs.
2. Install/verify `e2fsprogs/debugfs` plus existing host/QEMU/toolchain dependencies.
3. Run complete static gates, including the new deterministic-overlay/target-state regressions plus existing Git/QEMU/package provenance suites.
4. Run full official Anki backend from the verified deterministic overlay and persist fresh results/library hash.
5. Run all five real APKG integrations, including typed-answer coverage.
6. Run fresh ARMHF cross-build and ABI/GLIBC/export audit; ARMHF must independently verify the same overlay and start from a recreated Cargo target.
7. Supply **both** private PW6 inputs: extracted 5.19.6 rootfs and retained `pw6-rootfs.img` whose SHA-256 is `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
8. Run exact-rootfs QEMU; actual `-L` runtime must be the temporary tree freshly `rdump`ed from that exact verified image.
9. Run package/reproducibility/privacy/content gates and persist final ZIP/SHA-256/manifest/contents/all reports durably on GitHub.
10. Perform physical PW6 HIL separately after software-delivery hashes exist.

## Completion definition

**Not released.** Completion requires the full current-head source -> deterministic Anki overlay -> official backend/APKG -> ARMHF -> retained-image-bound + image-derived-runtime exact-rootfs QEMU -> package -> durable GitHub evidence chain. Physical PW6 acceptance is a separate final result.
