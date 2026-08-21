# VM lifecycle hardening — zombie operation-lock owners

Date: 2026-08-22 UTC

## Scope

This continuation investigated the newest branch-head regression around the sync wrapper fork/publication window. It is a lifecycle/collection-ownership change only; it does **not** replace the required full canonical host/rslib/ARMHF/package rerun or exact-PW6-rootfs QEMU smoke.

Starting branch head:

```text
9d4b6423a8e0f5fb761013145210183b40f5fc8f  test: reproduce sync fork-publication kill window
```

Relevant starting blobs:

```text
kindle-anki-port/scripts/sync.sh                  b8ec644293d2fe88261fb81011ee730fff04c8e9
kindle-anki-port/tests/test_sync_wrapper_signal.sh 70d07fe4ad479336941c913463c55ff22e15ddc1
```

## Reproduced defect

The new pre-publication SIGKILL fixture was reproduced against the then-current `sync.sh` in an isolated Linux execution environment.

Failure sequence:

1. The wrapper creates a gated child and begins atomically publishing the child's PID through `pid.next.$$ -> pid`.
2. The wrapper is SIGKILLed while a deliberately delayed `mv` is in progress.
3. The gated child detects that its wrapper died and exits before `exec kap-sync`, so it never touches the collection.
4. The orphaned gated child can remain as a zombie for a non-trivial interval.
5. `kill -0 <zombie-pid>` still succeeds.
6. The next `sync.sh` therefore classified the stale lock owner as live and returned `74` instead of reclaiming the lock and running the worker.

One captured failing trace ended with:

```text
stale_owner=<gated-child-pid>
kill -0 <gated-child-pid>        # succeeds because the process is Z
next sync status=74
expected status=7 from the fake worker
```

This is a real correctness problem rather than a test-only timing issue: a zombie cannot own the collection, but the previous liveness predicate treated it as a live operation owner.

## Fix

Both lifecycle wrappers now use a common policy implemented locally in each POSIX shell script:

```text
kill -0 PID must succeed
AND, when /proc/PID/stat is readable, process state must not be Z
```

Changes:

- `scripts/sync.sh`
  - added `pid_is_running()`;
  - stale-operation-lock checks now treat `Z` as dead/reclaimable;
  - reviewer PID verification uses the same liveness predicate.
- `scripts/launch.sh`
  - added the same `pid_is_running()` policy;
  - launch-side sync-lock exclusion no longer rejects a stale zombie owner;
  - reviewer PID verification uses the same liveness predicate.

The `/proc` check is fail-safe for non-Linux-like environments: if `/proc/PID/stat` cannot be read, behavior falls back to the previous `kill -0` test.

Canonical Git blobs after the fix:

```text
scripts/sync.sh   7381fca8bdef86c57c580a367f5647173f76c892
scripts/launch.sh 34ee8d5f106e31eb5e78509e1e6054c993bf9711
```

## Deterministic regression coverage

A new host fixture, `tests/test_zombie_operation_lock.sh`, creates an actual unreaped zombie child and proves both wrappers recover correctly while `kill -0` still succeeds for that PID.

It verifies:

1. a `mode=sync` zombie lock does not permanently reject a launcher;
2. the launcher reclaims the stale lock and starts its fake reviewer;
3. a `mode=sync` zombie lock does not reject a new sync operation;
4. the sync wrapper reclaims the stale lock, runs the fake worker, propagates its status `7`, and removes the lock.

The fixture is invoked through `sh` from `testenv/scripts/run-static-gates.sh`, so the GitHub Contents API's default non-executable mode for a newly created file is not a problem.

## Targeted commands and results

The following targeted reconstruction was run against the changed scripts/tests:

```sh
sh -n scripts/launch.sh
sh -n scripts/sync.sh

for i in 1 2 3 4 5; do
  sh tests/test_zombie_operation_lock.sh
done

for i in 1 2 3; do
  sh tests/test_sync_wrapper_signal.sh
done
```

Result:

```text
launch.sh syntax: PASS
sync.sh syntax: PASS
test_zombie_operation_lock.sh: 5/5 PASS
test_sync_wrapper_signal.sh:   3/3 PASS
```

Captured targeted log:

```text
KAP_ZOMBIE_LOCK_20260822.log
SHA-256 2a97d443b30b172d7e636464f8bfda759e10ce1d120257ab7c8ef97c0e007250
```

The log itself was generated in the isolated execution environment and is summarized here; no collection, credential, device identifier, or private runtime byte is included.

## Commits

```text
174d93d37bb78a666aa92eef51029f8555b91501  fix: reclaim zombie sync operation owners
dcb3e2ea9e6e4b175a9d33f21dc4ae90352dda62  fix: reclaim zombie launch operation owners
e4b928e7af7ebd3c7c562c3e23d53f153da0b4f4  test: cover zombie operation-lock owners
ccf259d885e489c766e4656f4d0a6be75f1672ce  test: gate zombie operation-lock recovery
58deb5ded87f30c375d86d696661757dc659d24b  test: keep zombie-lock regression output clean
```

Head at the end of this continuation:

```text
58deb5ded87f30c375d86d696661757dc659d24b
```

## Environment limitation for this continuation

The current isolated execution environment could not resolve external Git/HTTP hosts for a normal clone/fetch, so this continuation did not claim a fresh full canonical Anki build. Source persistence and branch-head reads/writes were performed through the authenticated GitHub connector, and the lifecycle files needed for the targeted reproduction were reconstructed exactly enough to exercise the defect and fix.

This is **not** a reason to hand ordinary compilation to the user. The required full build remains VM-owned and must be rerun when a build VM with the canonical checkout and pinned upstream/toolchain cache is available.

## Remaining release work

1. Materialize the current canonical branch head and run `run-static-gates.sh` in full.
2. Rerun pinned Anki 26.08.1 `rslib` tests and the five real-APKG C-ABI integrations.
3. Rerun ARM hard-float cross-build and ABI/GLIBC audits from the same head.
4. Obtain the checksum-matching PW6 5.19.6 firmware/rootfs private input and run exact-rootfs QEMU smoke.
5. Rebuild and audit the final package from the release head and persist ZIP, SHA-256, manifest, contents and reports in GitHub.
6. Keep physical PW6 acceptance separate from all VM/QEMU evidence.
