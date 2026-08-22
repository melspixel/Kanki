# ADR 0005: Serialize collection operations with an inherited kernel lock

- Status: accepted
- Date: 2026-08-22

## Context

The launcher historically created `.kanki.lock/pid`, while standalone sync
only checked whether that directory existed. The check and the later
collection open were separate operations. A launcher could therefore acquire
the directory after sync's check, or two standalone sync processes could both
pass the check and open the same collection. PID-based stale cleanup also used
unconditional recursive deletion, so one exiting/recovering wrapper could
remove metadata published by another owner.

Making the directory protocol more elaborate would still leave PID reuse,
publication and wrapper-`SIGKILL` windows. In particular, a sync or reviewer
worker may continue using the collection after its shell wrapper dies.

The authenticated PW6 5.19.6 userspace provides util-linux `flock` 2.37.4 with
nonblocking file-descriptor locks. Linux associates that lock with the open
file description, which is inherited across `fork`/`exec` and released after
the last inheriting process closes it.

## Decision

The canonical package contains one manifest-owned
`.kanki.operation.lock` regular file. Runtime code opens but never unlinks or
replaces that inode.

`kanki-launch.sh` obtains an exclusive nonblocking lock on descriptor 9 before
starting any collection owner and holds it across the reviewer/internal-sync
lifecycle. The reviewer and launcher-initiated sync worker inherit descriptor
9. Audio and renderer-diagnostics children explicitly close it. Standalone
`kanki-sync.sh` must acquire the same lock before it can migrate credentials,
back up or open the collection. An internal sync accepts the inherited
descriptor only when `/proc` resolves it to the manifest-owned file and the
exact launcher owner/mode metadata matches.

Both wrappers supervise the foreground collection worker and forward
HUP/INT/TERM. If a wrapper is killed without cleanup, its still-running worker
continues to hold the inherited kernel lock. The lock is released by the
kernel when the final collection worker exits. `.kanki.lock/{pid,mode}` is
bounded diagnostic metadata only; it is replaced only while holding the
kernel lock and is never used to reclaim that lock.

Host contracts execute contention and inherited-worker lifetime behavior. The
fixed-firmware rootfs audit repeats the same probe with the actual PW6
`/usr/bin/flock` and BusyBox shell. Physical launch/sync/suspend/USB behavior
remains a PW6 hardware gate.

## Boundaries

This decision serializes process ownership; it does not replace Anki's
collection, scheduling or sync semantics and does not add another collection
implementation. It never locks, deletes, replaces or installs anything below
`/mnt/us/anki_data`, and it does not touch `/mnt/us/extensions/ranki`.

Install-integrity verification still runs before the helper or lock file is
opened. The lock file is a package component covered by `MANIFEST.sha256`, not
mutable user state. A missing fixed-firmware `flock` implementation is an
explicit compatibility failure, not a reason to fall back to path checks.

## Rejected alternatives

- Check whether a directory or PID file exists: this is a TOCTOU observation,
  not mutual exclusion.
- Delete a lock directory after `kill -0`: PID reuse and concurrent stale
  recovery can delete a new owner's state.
- Release the wrapper lock before spawning the worker: this reopens the exact
  fork/publication race the lock is intended to close.
- Let audio/diagnostics inherit descriptor 9: unrelated long-lived helpers
  could keep the collection unavailable after its real owner exits.
- Rely only on SQLite locking: it does not express the required reviewer/sync
  lifecycle or duplicate-window behavior and discovers conflicts too late.
