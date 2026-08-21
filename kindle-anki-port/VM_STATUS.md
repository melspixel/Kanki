# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22 UTC

## Current state

VM-side continuation remains active with permission to install ordinary build/test dependencies. GitHub Actions quota exhaustion is not treated as a compiler blocker.

The former semantic-backend privacy blocker is resolved by the narrow `crate::services::kap_bridge`. Persisted checkpoints include full official Anki rslib `539/539`, five real-APKG C-ABI integrations, ARMHF hard-float binaries, ABI/GLIBC audit, package audit, and QEMU static ARM sanity.

## Latest material advances

The 2026-08-22 continuation added exact-source deterministic sync and reviewer runtime fixtures and then found/repaired a real lifecycle race.

```text
36c73d49251ca73d8448434b247e722c46c4fa99  reject conflicting full-sync directions
4a27352fa7718e2d8e48fc603582e7d55f2b0653  sync fault injection and sanitized tracing
78fbfa38c4599673eb356f88597bf7ea0707e9c1  expanded sync decision/error/abort matrix
a3bdeaf924b5fb6d802c9454ac4c5435d3eb5b16  reviewer runtime fixture matrix
3e139cb006be449b385ad26470ebe9327dc15393  reviewer runtime fixture added to static gate
e72413501414507d4eb03ef3199000772be2dcf7  serialize launcher startup through PID publication
fdb222d23384df1d3add2f4d84321709edd8ab41  hold shared operation lock across sync
fe1b2084654361bc72ef047b07395f5422892823  fake-app process tracing for lifecycle races
e949a6b8c2b0718dbd39e06af311c52cb635ba5d  lifecycle race/exclusion/stale-lock regression matrix
```

Results:

```text
test_sync_worker: ok
test_reviewer_runtime_fixtures: ok (10 fixture groups)
test_lifecycle: ok
```

The lifecycle defect was reproduced before repair: two near-simultaneous launch requests could both pass the PID check and start two reviewer processes. A shared atomic operation-lock directory now serializes launch through child PID publication and gives sync exclusive collection ownership for its full worker lifetime. Tests require exactly one start plus one raise under the double-launch regression, launch refusal while sync owns the lock, and stale/dead lock recovery.

Detailed evidence: `docs/VM_CONTINUATION_20260822.md`.

## Active blockers / next execution targets

The next build target is a **full rebuild from a materialization of the then-current canonical GitHub head**: complete static gate, official rslib tests, real-APKG integration, ARMHF cross-build, ABI/GLIBC audit and package audit. Previous green binaries/package remain checkpoint evidence because their provenance predates current source.

Exact-rootfs dynamic QEMU is also open. The VM retains verified PW6 5.19.6 extraction/oracle reports and hashes, but the complete extracted rootfs bytes are absent. Reports are not accepted as a substitute for runtime input.

In parallel, VM-side source review can continue for deterministic state-machine, process-lifecycle and collection-ownership defects that do not require Rust rebuilding or target hardware.

## Persistence rule

`HANDOFF.md` is the authoritative continuation point and `PROGRESS.md` is the phase matrix. Every material source/test/build change is synchronized to the `kindle-anki-port` branch. Temporary VM archives are checkpoint/transfer objects only and may not be called releases.

## User involvement

No user/local-host compilation action is requested. `CODEX_COORDINATION.md` contains a narrowly scoped private-input task for a networked worker if the exact PW6 rootfs needs to be transported into the VM. Physical PW6 work starts only after a final GitHub-persisted package and test-bundle checksum exist.
