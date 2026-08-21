# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22 UTC

## Current state

VM-side continuation remains active with permission to install ordinary build/test dependencies. GitHub Actions quota exhaustion is not treated as a compiler blocker.

The former semantic-backend privacy blocker is resolved by the narrow `crate::services::kap_bridge`. Persisted checkpoints include full official Anki rslib `539/539`, five real-APKG C-ABI integrations, ARMHF hard-float binaries, ABI/GLIBC audit, package audit, and QEMU static ARM sanity.

The canonical branch has since advanced through build-entrypoint, reproducibility and package-provenance hardening. These newer source changes still require one full immutable-head rebuild before any package can be release evidence.

## Latest material advances

### Lifecycle and reviewer/sync hardening

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

Persisted results:

```text
test_sync_worker: ok
test_reviewer_runtime_fixtures: ok (10 fixture groups)
test_lifecycle: ok
```

The lifecycle defect was reproduced before repair: two near-simultaneous launch requests could both pass the PID check and start two reviewer processes. A shared atomic operation-lock directory now serializes launch through child PID publication and gives sync exclusive collection ownership for its full worker lifetime. Later targeted work also closed wrapper-SIGKILL and zombie-owner stale-lock windows.

Detailed evidence: `docs/VM_CONTINUATION_20260822.md`, `docs/VM_LIFECYCLE_HARDENING_20260822.md`, and `docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md`.

### Build/package provenance hardening

The canonical build/test entry points now delegate to the maintained host, ARMHF, QEMU and package gates rather than weaker compatibility wrappers. External sysroot hashing is path-independent, the VM driver cannot report broad success without all required gates, and package ZIP metadata is normalized across timezone and umask. See `docs/VM_BUILD_ENTRYPOINT_HARDENING_20260822.md`.

The release packager now also refuses stale cross-build outputs: `ARMHF-GATES.txt` must record PASS and `BUILD-PROVENANCE.txt` must match both the release `BUILD_COMMIT` and pinned Anki commit.

That production hardening exposed a deterministic static-test regression: `tests/test_package_reproducibility.py` still generated placeholder ARMHF provenance and therefore could no longer pass the production package preconditions. The fixture has been repaired without weakening package validation and now also contains negative stale-source and stale-Anki provenance cases.

```text
3001f4e1d9bfe91714bd76a21fbdbf32109fd1b0  package: bind release archive to ARMHF provenance
03a4e00be7a9d31848879430cdb6046eb2a6e536  test: bind package reproducibility fixture to ARMHF provenance
286938ddf9ae5ee85972cebf97c52fa599ce2a67  repaired test blob
```

Detailed evidence: `docs/VM_PACKAGE_PROVENANCE_REGRESSION_20260822.md`.

## Active blockers / next execution targets

The next build target is a **full rebuild from a materialization of the then-current canonical GitHub head**: complete static gate, official rslib tests, real-APKG integration, ARMHF cross-build, ABI/GLIBC audit and package audit. Previous green binaries/package remain checkpoint evidence because their provenance predates current source.

The current isolated execution container still cannot resolve public `github.com`, so it cannot truthfully claim a fresh canonical checkout, pinned upstream build or full static-gate execution. This is an environment limitation, not a request to move normal compilation onto the user's local host.

Exact-rootfs dynamic QEMU is also open. The VM retains verified PW6 5.19.6 extraction/oracle reports and hashes, but the complete extracted rootfs bytes are absent. Reports are not accepted as a substitute for runtime input.

In parallel, VM-side source review can continue for deterministic build, state-machine, process-lifecycle and collection-ownership defects that do not require Rust rebuilding or target hardware.

## Persistence rule

`HANDOFF.md` is the authoritative continuation point and `PROGRESS.md` is the phase matrix. Every material source/test/build change is synchronized to the `kindle-anki-port` branch. Temporary VM archives are checkpoint/transfer objects only and may not be called releases.

## User involvement

No user/local-host compilation action is requested. `CODEX_COORDINATION.md` contains a narrowly scoped private-input task for a networked worker if the exact PW6 rootfs needs to be transported into the VM. Physical PW6 work starts only after a final GitHub-persisted package and test-bundle checksum exist.
