# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-22 UTC

## Canonical continuation point

- Repository: `melspixel/Kanki`
- Branch: `kindle-anki-port`
- Project root: `kindle-anki-port/`
- Official Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- Platform-reference report commit: `a4c9f0c83158fcfcdd71bddb31d5dad16dd69e4b`
- Always resolve the live branch HEAD before building; documentation/evidence commits advance HEAD.

Read before continuing, in order:

```text
HANDOFF.md
PROGRESS.md
CODEX_COORDINATION.md
docs/TEST_ENVIRONMENT.md
VM_RUNBOOK.md
```

Newest detailed evidence:

```text
docs/VM_PLATFORM_REFERENCE_20260822.md
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
docs/REFERENCE_IMPLEMENTATIONS.md
docs/VM_CURRENT_HEAD_WEB_NATIVE_20260822.md
docs/VM_REVIEWER_FIXTURE_DEPENDENCY_20260822.md
docs/VM_ANKI_OVERLAY_PROVENANCE_HARDENING_20260822.md
docs/VM_GIT_IDENTITY_FAIL_CLOSED_20260822.md
docs/VM_QEMU_IMAGE_RUNTIME_BINDING_20260822.md
```

## Product boundary

This is an independent port of desktop Anki to Kindle PW6. It is not a Ranki
patch set and not a continuation of `rewrite-v1`.

Official Anki owns:

```text
collection, schema and transactions
scheduler and FSRS
queue construction and answer transitions
template rendering and cloze
typed-answer extraction and comparison
AV extraction and media metadata
sync, full sync, media sync and undo
```

Kindle code owns only:

```text
GTK2/WebKitGTK1 platform integration
persistent reviewer shell and generic old-WebKit compatibility
touch/page navigation and system keyboard focus
native audio and sync workers
process/collection ownership and lifecycle
ARMHF build, exact-rootfs QEMU and packaging
```

Production must not contain Ranki or `rewrite-v1` runtime code, `LD_PRELOAD`,
deck-name routing, note-type patches, a local scheduler/renderer/sync
reimplementation, firmware, proprietary rootfs libraries, user collection/media,
credentials or device identifiers.

## Reference-first platform policy

Existing Kindle projects are now explicitly used as pinned behavior references
instead of treating Lab126 as a blank slate:

```text
crazy-electron/ranki       d671ee657f0c411474d2afff3bf9cbb49be2fb44
kbarni/kindlepuzzles       9f67dd04634d16dfa2e8eeef13eb582b8225e49e
emlyn-m/em-dash            f8c260636dc4fa811c7e470b8b4626985a188172
anakod/kindle-explorer     134d04e20d4eaa83a51369eaa80fd3fa007a4d46
```

The exact reference, observed behavior, license status and clean-room/copying
policy are recorded in `docs/REFERENCE_IMPLEMENTATIONS.md`. Ranki remains a
platform-behavior reference, not a runtime/build dependency. Repositories whose
license is not established are reference-only; compatible copied code must
retain its required notice and exact origin.

## Latest material checkpoint — Kindle window identity and typed-answer IME

Starting source:

```text
ae349e0126bc95d4350acc6885e4ee443a91c88e
```

The checkpoint adds:

- Lab126/Awesome-compatible GTK title:
  `L:A_N:application_ID:com.melspixel.kindleankiport_PC:N`;
- `ime/open` and `ime/close` operations on the existing `kap://v1` protocol;
- typed-answer focus/blur integration in the persistent reviewer;
- direct `/usr/bin/lipc-set-prop -s` execution with `execl()`, no shell;
- bounded child waiting, forced reap and cleanup integration;
- startup normalization when a crashed prior process may have left the keyboard visible;
- duplicate open/close suppression after keyboard state becomes known;
- closure before reveal, back, non-question state and application cleanup;
- executable C, JavaScript and source/reference contract regressions;
- manual-only GitHub Actions to stop exhausted-runner noise.

Maintained tests now include:

```text
tests/test_ime_runtime.js
tests/test_platform_adapter.c
tests/test_platform_reference_contract.py
```

Verified targeted results:

```text
web/ime.js syntax                                      PASS
focus/blur/reveal/state/back ordering                  PASS
C99 -Wall -Wextra -Werror platform test                PASS
startup stale-keyboard close                           PASS
open value <app-id>:abc:1                              PASS
duplicate open suppression                             PASS
reveal-time close before semantic dispatch             PASS
native app composition and title macro harness         PASS
reference/license/independence contract                PASS
manual-only workflow contract                          PASS
```

Persisted log:

```text
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
SHA-256 42b0059bc09828ae077ab926cb9a23121dbcfff27720ffebf4767b67c413692a
```

This is current-source targeted evidence, not a complete `run-static-gates.sh`
pass and not a Kindle release.

## Previous current-source targeted checkpoints

The branch also has current-source targeted evidence for:

```text
audio queue syntax/lifecycle                           PASS
CSS compatibility                                      PASS (9 fixtures)
reviewer runtime                                       PASS (10 groups)
WebKit1 contracts                                      PASS
kap-app strict host C build/audio supervision          PASS
kap-audio strict host C build/self-test                PASS
kap-sync strict host C build/self-test                 PASS
launcher/sync wrapper/zombie-lock lifecycle paths      PASS
```

See `docs/VM_CURRENT_HEAD_WEB_NATIVE_20260822.md` and related reports. These
remain targeted checkpoints until one complete clean-current-head invocation is
persisted.

## Historical green checkpoints — regression evidence only

```text
official Anki rslib                    539 passed, 0 failed
five real APKG C-ABI reviewer flows    PASS
real APKG typed-answer and AV observed PASS
reviewer runtime fixture groups        10 PASS
sync worker                             PASS
kap-app                                ARM EABI5 hard-float, GLIBC_2.4
kap-audio                              ARM EABI5 hard-float, GLIBC_2.4
kap-sync                               ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so                      ARM EABI5 hard-float, max GLIBC_2.18
PW6 target libc oracle ceiling         GLIBC_2.35
```

These predate later source/overlay/Cargo/QEMU provenance hardening and must be
rerun from the eventual final clean source identity.

The old installer remains stale and must never be relabeled final:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Exact PW6 5.19.6 identity

Canonical manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Pinned values:

```text
firmware version          5.19.6 / 4832160042
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
target GLIBC max          2.35
```

Release L2 requires both the separately verified extracted rootfs and retained
full `pw6-rootfs.img`. QEMU `-L` must point only at a temporary tree freshly
`debugfs rdump`ed from the verified image. The proprietary bytes are private and
never committed.

## Release-provenance invariants

A valid non-hardware release is one coherent chain:

```text
resolvable clean project HEAD^{commit}
+ exact pinned Anki HEAD^{commit}
+ deterministic allowed Anki overlay only
+ fresh gate-owned Cargo target
+ complete static gates
+ official Anki cargo check/test/release build
+ five real APKG integrations including typed answer
+ fresh KindleHF ARMHF build and ELF/ABI/GLIBC/export audit
+ exact retained-image-derived PW6 QEMU for backend/audio/sync
+ QEMU-bound reproducible/privacy-audited package
+ final ZIP, SHA-256, internal manifest, contents and reports persisted durably
```

Synthetic fixtures, old ZIPs, copied targets, non-Git trees, selected rootfs
files or historical results cannot become final provenance.

## Current environment limitation

The current isolated Linux VM has sufficient CPU/RAM/disk and root access, but
ordinary outbound networking remains blocked:

- normal DNS/Git/curl cannot resolve or connect to GitHub;
- direct-IP probes also failed;
- Rust 1.92.0, Cargo dependencies, protoc, qemu-user, debugfs and KindleHF are
  not yet bootstrapped into this VM;
- a complete clean live worktree is not currently materialized locally;
- the private PW6 rootfs tree/image pair is absent.

The same network condition has been reproduced through multiple independent
probes and is now a declared infrastructure blocker, not a source-test result.
It does not justify weakening gates or delegating ordinary compilation to the
user's host.

Intermediate status/logs are also stored under Google Drive:

```text
GPT周转/Kindle-Anki-Port/
```

## Ordered next actions

1. Resolve the live branch HEAD again.
2. Materialize a complete clean Git checkout of that exact commit in the VM.
3. Import/install an offline pinned bundle containing Rust 1.92.0, Cargo cache,
   protoc, QEMU/debugfs and KindleHF 2025.05, or restore normal VM networking.
4. Run complete `testenv/scripts/run-static-gates.sh`, including the new
   platform-reference tests and full real `native/app.c` host build.
5. From the same identity run official Anki `cargo check`, all 539 rslib tests,
   release build and record `libanki.so` SHA-256.
6. Run all five real APKG integrations including typed answer.
7. Rebuild `libanki-kindle.so`, `kap-app`, `kap-audio`, `kap-sync` for ARMHF and
   repeat file/readelf/nm/GLIBC/RPATH/dependency/export audit.
8. Supply and verify both exact private PW6 inputs.
9. Run image-derived QEMU backend/audio/sync.
10. Only after QEMU passes, package, audit reproducibility/privacy/content and
    persist the final release assets.
11. Begin physical PW6 HIL separately: e-ink, touch, IME, audible Bluetooth,
    fullscreen re-entry, suspend/resume, USB, Wi-Fi, sync and 50 launch/exit cycles.

## Completion rule

**Not released.**

The latest platform checkpoint substantially lowers the Kindle keyboard/window
integration risk, but it does not replace the clean-current-head Anki, ARMHF,
exact-rootfs QEMU, package and physical-device gates.
