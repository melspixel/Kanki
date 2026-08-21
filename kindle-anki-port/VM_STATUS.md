# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22 UTC

## Current state

VM-side continuation remains active with permission to install ordinary build/test dependencies. GitHub Actions quota exhaustion is not treated as a compiler blocker.

The former semantic-backend privacy blocker is already resolved by the narrow `crate::services::kap_bridge`; it is no longer the active repair target. Persisted checkpoints include full official Anki rslib `539/539`, five real-APKG C-ABI integrations, ARMHF hard-float binaries, ABI/GLIBC audit, package audit, and QEMU static ARM sanity.

## Latest material advances

The 2026-08-22 continuation added and locally executed exact-source deterministic fixtures before persisting them to GitHub:

```text
36c73d49251ca73d8448434b247e722c46c4fa99  reject conflicting full-sync directions
4a27352fa7718e2d8e48fc603582e7d55f2b0653  sync fault injection and sanitized tracing
78fbfa38c4599673eb356f88597bf7ea0707e9c1  expanded sync decision/error/abort matrix
a3bdeaf924b5fb6d802c9454ac4c5435d3eb5b16  reviewer runtime fixture matrix
3e139cb006be449b385ad26470ebe9327dc15393  reviewer runtime fixture added to static gate
```

Results:

```text
test_sync_worker: ok
test_reviewer_runtime_fixtures: ok (10 fixture groups)
```

The sync fixture verifies, among other paths, signal-driven `abort -> close -> core_free` ordering, destructive-direction ambiguity rejection, error cleanup, argument propagation and credential non-disclosure. The reviewer fixture drives production `window.kapReviewer` through a dependency-free fake DOM and covers typed input, audio/replay routing, script replacement, nested scroll flattening, state transitions, error telemetry and touch paging.

Detailed evidence: `docs/VM_CONTINUATION_20260822.md`.

## Active blockers / next execution targets

The next build target is a **full rebuild from a materialization of the then-current canonical GitHub head**: complete static gate, official rslib tests, real-APKG integration, ARMHF cross-build, ABI/GLIBC audit and package audit. Previous green binaries/package remain checkpoint evidence only because their provenance predates the current canonical source head.

Exact-rootfs dynamic QEMU is also still open. The VM retains verified PW6 5.19.6 extraction/oracle reports and hashes, but the complete extracted rootfs bytes are absent. Reports are not accepted as a substitute for the runtime input.

## Persistence rule

`HANDOFF.md` is the authoritative continuation point and `PROGRESS.md` is the phase matrix. Every material source/test/build change is synchronized to the `kindle-anki-port` branch. Temporary VM archives are checkpoint/transfer objects only and may not be called releases.

## User involvement

No user/local-host compilation action is requested. `CODEX_COORDINATION.md` already contains a narrowly scoped private-input task for a networked worker if the exact PW6 rootfs needs to be transported into the VM. Physical PW6 work starts only after a final GitHub-persisted package and test-bundle checksum exist.
