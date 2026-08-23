# Kindle Anki Port — VM Continuation 2026-08-22

## Scope

This continuation started from the authoritative `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md` on branch `kindle-anki-port`.

The branch head at the start of this run was:

```text
d27258cee6bef948809d12ac38c786e05870cd9f
```

The run concentrated on non-hardware gaps that can be advanced without the exact PW6 rootfs: deterministic sync behavior, executable reviewer runtime fixtures, and lifecycle concurrency safety.

## Sync worker hardening

A CLI ambiguity was found in `native/sync.c`: supplying both `--full-upload` and `--full-download` silently allowed the later option to win. The worker now rejects conflicting full-sync modes with status 64 instead of making a destructive-direction decision implicitly.

Persisted commits:

```text
36c73d49251ca73d8448434b247e722c46c4fa99  sync: reject conflicting full-sync modes
4a27352fa7718e2d8e48fc603582e7d55f2b0653  test: add deterministic sync error and shutdown tracing
78fbfa38c4599673eb356f88597bf7ea0707e9c1  test: expand sync decision error and abort fixtures
```

`tests/fake_sync_backend.c` now supports deterministic fault injection and sanitized event tracing for:

- backend initialization failure;
- collection-open failure;
- incremental-sync failure;
- full-sync failure;
- media-status failure;
- abort failure;
- one-shot and indefinitely active media-sync states;
- endpoint/timeout/full-sync argument tracing without recording the hkey.

`tests/test_sync_worker.sh` now covers:

- no-change incremental sync;
- endpoint and timeout propagation;
- required-action values 2/3/4 and unknown values;
- explicit full upload/download, server media USN and timeout propagation;
- media polling;
- open/sync/full/media error cleanup;
- SIGTERM during an indefinitely active media poll;
- required shutdown ordering `abort -> close -> core_free`;
- missing/empty hkey;
- missing backend library;
- backend initialization failure;
- conflicting full-upload/full-download flags;
- uint32 timeout overflow;
- credential non-disclosure in worker logs and traces.

The exact GitHub blobs used for local validation were verified with Git object hashes:

```text
native/sync.c                     ec6c109f8d331c31aae403b45f9ff09f83272fa8
tests/fake_sync_backend.c         4ea347196aaa6ead68283867fded7fec21dc536c
tests/test_sync_worker.sh         17d4874a12a758f1fac1977a8e3ac20fb41fc95d
```

Validation command/result:

```text
cd <materialized-kindle-anki-port>
sh tests/test_sync_worker.sh

test_sync_worker: ok
```

The worker and fake backend are compiled by the fixture with:

```text
-O2 -std=c99 -Wall -Wextra -Werror
```

## Reviewer runtime fixture matrix

Prior coverage checked ES5/static contracts and CSS transformations, but did not execute the persistent reviewer shell through its public `window.kapReviewer` API. A dependency-free Node/vm harness was added:

```text
tests/test_reviewer_runtime_fixtures.js
```

Persisted commits:

```text
a3bdeaf924b5fb6d802c9454ac4c5435d3eb5b16  test: add reviewer runtime fixture matrix
3e139cb006be449b385ad26470ebe9327dc15393  test: include reviewer runtime fixtures in static gate
```

The harness uses a deliberately small fake DOM and exercises ten fixture groups against the production `web/reviewer.js`:

- startup/ready protocol;
- plain mixed CJK/Latin question rendering;
- body-class, CSS, interval and automatic audio propagation;
- typed-answer input installation, focus and reveal payload;
- inline-script node replacement and duplicate desktop-Anki replay-control removal;
- `[anki:play:*]` marker replacement and replay/TTS routing;
- nested bounded vertical-scroll flattening;
- answer-separator scrolling;
- finished/answer/bury state transitions;
- backend/render failure telemetry plus touch/page behavior.

Before execution, the VM verified that the local reviewer source was byte-for-byte the current GitHub blob by recomputing the Git blob SHA:

```text
web/reviewer.js   a84e4561ae9d98fa04c009bb930a8a6d5129e533  MATCH
web/css_compat.js 289c98c482f7631efb5b621e5ee378e82ceebb70  MATCH
```

Local fixture result:

```text
test_reviewer_runtime_fixtures: ok (10 fixture groups)
```

`testenv/scripts/run-static-gates.sh` now executes this runtime matrix in addition to the existing syntax, source, CSS, native, lifecycle and sync gates.

## Launch/sync lifecycle concurrency repair

A real startup race was identified in `scripts/launch.sh`. The old sequence checked `.kap.pid`, then performed manifest verification and first-open backup work, and only afterwards started `kap-app` and published the child PID. Two nearly simultaneous launcher invocations could therefore both observe no live PID and both start a reviewer against the same collection.

A deterministic regression reproduced the defect by deliberately delaying the pre-open `cp`. Before the repair, the trace contained two independent application starts:

```text
start 2477
start 2480
```

This is not only a cosmetic single-instance issue: a concurrent reviewer or reviewer/sync pair can cause two processes to open the same collection, which is an unacceptable lifecycle/data-safety condition.

The repair introduces one shared atomic operation-lock directory:

```text
${KAP_OPERATION_LOCK_DIR:-$APP/.kap-operation.lock}/
  pid
  mode    # launch | sync
```

`mkdir` is used as the atomic ownership primitive. The launcher holds the lock from single-instance inspection through child PID publication; a second launcher waits until publication and then raises the verified existing instance. Sync acquires the same lock and keeps it for its entire worker lifetime, so a launch cannot open the collection while sync owns it. Dead/stale owners can be reclaimed, while a live sync owner causes launch to fail closed with status 74.

Persisted commits:

```text
e72413501414507d4eb03ef3199000772be2dcf7  lifecycle: serialize launch startup and sync ownership
fdb222d23384df1d3add2f4d84321709edd8ab41  lifecycle: hold shared operation lock across sync
fe1b2084654361bc72ef047b07395f5422892823  test: trace fake app process starts for lifecycle races
e949a6b8c2b0718dbd39e06af311c52cb635ba5d  test: cover launch races sync exclusion and stale locks
```

Exact current blobs used for the local regression run:

```text
scripts/launch.sh          13bd8618773b0d53b2f92cc9221861629de2adf7
scripts/sync.sh            6c466df5364cc7ec72a9635fc5ce941080ba41fe
tests/fake_app.c           3964cbfbe639ea218fe8b538bc734ebbeb32167b
tests/test_lifecycle.sh     5d9ea402c5353aa2ef411e2968b9498c0759383b
```

The expanded lifecycle fixture now verifies:

- ordinary launch, backup, PID cleanup, and lock cleanup;
- verified resident-instance raise;
- foreign/stale PID handling before sync;
- lock release on missing sync executable;
- deterministic concurrent double-launch regression: exactly one application starts and the second request raises it;
- launch refusal while an active sync owns the collection operation lock;
- lock release after sync completion;
- stale/dead operation-lock recovery.

Validation commands/results:

```text
cd <materialized-kindle-anki-port>
sh -n scripts/launch.sh
sh -n scripts/sync.sh
cc -O2 -std=c99 -Wall -Wextra -Werror tests/fake_app.c -o <fixture-app>
sh tests/test_lifecycle.sh

test_lifecycle: ok
```

The sync worker fixture was rerun after the lifecycle changes and remains green:

```text
test_sync_worker: ok
```

The operation lock is runtime state under the application directory and is neither a build input nor a release artifact; package policy must continue to reject transient PID/lock state from distributable archives.

## Current source/test frontier

The material code/test head reached in this continuation before documentation-only commits was:

```text
e949a6b8c2b0718dbd39e06af311c52cb635ba5d
```

Subsequent documentation commits naturally move the branch head beyond this SHA. This source/test frontier advances deterministic coverage and fixes a reproduced lifecycle race, but is not yet a release-provenance build. A full canonical-head host/rslib/ARMHF/package rebuild still must be run from a VM checkout/materialization of the then-current branch head.

## Exact-rootfs status

The VM still contains the previously generated PW6 5.19.6 oracle reports and exact hashes, but not the complete extracted rootfs bytes. The retained oracle records confirm the prior extraction used a rootfs image whose SHA-256 was:

```text
b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

Only reports/hashes survived; they are not a substitute for the rootfs runtime input required by `run-qemu-smoke.sh`. Exact-rootfs dynamic QEMU therefore remains pending. This remains an external private-input limitation, not a compiler or source blocker.

## Ordered next actions

1. Re-materialize the then-current canonical GitHub head in a build-capable VM and rerun the whole static gate, official Anki rslib tests, real-APKG integration, ARMHF build, ABI/GLIBC audit and package audit from that exact head.
2. Supply the checksum-verified PW6 5.19.6 rootfs privately and execute `verify-pw6-rootfs.py` plus backend/audio/sync QEMU smoke tests.
3. Continue deterministic lifecycle/reviewer/core review, prioritizing state-machine and collection-ownership failures that can be reproduced without target hardware.
4. Produce and durably persist the final canonical-head package, checksum, manifest, package contents and test reports only after all non-hardware gates are green.
5. Start physical PW6 acceptance only after the final GitHub-persisted package/test-bundle checksums exist.

## Completion status

Not released. Hardware acceptance has not started, and no VM/QEMU result may substitute for the physical PW6 gate.
