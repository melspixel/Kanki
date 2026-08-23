# VM lifecycle hardening — 2026-08-22

## Scope

This continuation focused on launch/sync ownership and signal behavior that can be tested deterministically without a PW6 rootfs. The canonical branch was advanced from `6aa52cb4faf0a48ac46fb8ea23557db6e4ea0f46` through the commits listed below.

## Defect reproduced

The pre-fix `scripts/sync.sh` owned `.kap-operation.lock` with the wrapper shell PID and then executed `kap-sync` in the foreground without TERM/INT/HUP forwarding.

A deterministic fake-worker reproduction sent SIGTERM to the wrapper while the worker was alive. Observed pre-fix state:

```text
wrapper_status=143
child_alive=yes
lock_exists=yes
trace=start
```

The remaining lock still named the now-dead wrapper rather than the live worker. A later launcher could therefore classify the lock as stale and reclaim it while the orphaned sync worker still had the collection open. That creates a real concurrent reviewer/sync collection-open hazard.

## Fix

### Sync wrapper

`scripts/sync.sh` now:

- starts the sync worker under explicit supervision;
- atomically transfers the operation-lock owner record from the wrapper PID to the real worker PID before waiting;
- forwards TERM, INT and HUP to the worker;
- waits for the worker and propagates its normal exit status;
- returns conventional signal statuses (`143`, `130`, `129`);
- only releases a lock whose owner record still matches the owner it controls;
- uses an ownership-checked recursive directory removal so a signal cannot strand an empty lock between unlink and `rmdir`;
- preserves the worker-owned lock if the wrapper itself is killed with SIGKILL.

This means an untrappable wrapper death no longer makes the collection look free while the real sync process is still running.

### Launcher

`scripts/launch.sh` received the same ownership-aware lock release rule. Its signal forwarding now also returns conventional shell signal statuses rather than the former hard-coded `128`.

During targeted testing, a first ownership-aware implementation exposed a second interruption window: SIGTERM could arrive after the owner files were unlinked but before `rmdir`, leaving an empty lock directory. Reproduction:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=yes
```

The release primitive was corrected to perform an ownership check followed by `rm -rf "$OP_LOCK"`. The same harness then produced:

```text
launch_signal_status=143 child_alive=no pidfile=no lock=no
```

## Regression coverage

New `tests/test_sync_wrapper_signal.sh` covers:

1. TERM forwarding and status `143`;
2. worker death and lock cleanup after a trapped wrapper signal;
3. wrapper SIGKILL while the worker remains alive, with the operation lock still owned by the worker PID;
4. propagation of a normal worker failure status (`7`);
5. absence of a leftover operation lock after normal failure cleanup.

`tests/test_lifecycle.sh` now also covers launcher TERM forwarding, status `143`, reviewer termination, PID-file cleanup and operation-lock cleanup.

`testenv/scripts/run-static-gates.sh` runs the new sync-wrapper regression between the lifecycle and sync-worker gates.

Targeted local harnesses passed after the final release primitive correction. A full canonical-head static/backend/ARMHF rerun remains a release-provenance gate and is not inferred from these targeted tests.

## Commits

```text
af25dabf7e8650e27b777855b0a97302ca6c9dc2  fix: keep sync operation lock tied to worker lifetime
779f7ba7d7d5c5efb3d829da6dc98e125846c7f4  test: cover sync wrapper signal and lock ownership
170e362a2f105ecb593659847fb491c7952d2fb5  test: gate sync wrapper signal supervision
17cac812832f9e6ac3563f8da7bec865827c5b95  fix: make launcher lock release ownership-aware
ef18b1b5fe885273258c718da354b83848d8a4fe  test: cover launcher signal cleanup and status
f1919f42bd59331d470d1aaa53987b16ed3b37d9  fix: make launcher lock release interruption-safe
d589345428f28777cf413f97ac0602d565dbfa90  fix: make sync lock release interruption-safe
```

## Remaining lifecycle review

The operation lock now fails closed across the reproduced wrapper-death case. Still worth retaining in the full release rerun:

- double-launch regression;
- reviewer/sync exclusion;
- stale dead-owner recovery;
- launcher-triggered sync followed by relaunch;
- signal/error cleanup;
- package exclusion of runtime PID/lock state.

No hardware acceptance is claimed by this report.
