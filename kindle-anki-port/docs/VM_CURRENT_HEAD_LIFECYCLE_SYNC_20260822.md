# Current-head lifecycle and sync checkpoint — 2026-08-22

## Scope

This checkpoint ran the canonical lifecycle, sync-wrapper, zombie-lock and native sync-worker regression groups using exact Git blobs from branch source commit:

```text
0ad4c67e8e814a01bb9bd0acb28cabc3cf931784
```

It is a current-head static-gate subset. It is not an official Anki backend/APKG/ARMHF/QEMU/package result.

## Materialization audit

The first partial-tree attempt failed before test logic because the local recovery had dropped the repository executable bit from `scripts/sync.sh`. Git tree metadata confirms both launcher scripts are `100755`; restoring that exact mode resolved the failure without changing bytes.

A later attempt reached sync-worker compilation and showed that two exact source inputs were absent from the transient subset: `core/kap_core.h` and `native/sync.c`. They were restored from Git blobs `3023e5c5…` and `ec6c109f…` and checked with `git hash-object`. No source, assertion or gate was weakened.

## Final results

```text
shell syntax                  PASS
lifecycle                     PASS
sync wrapper signal/death     PASS
zombie operation lock         PASS
native sync worker            PASS
```

The wrapper test's two `Killed` lines are expected: it deliberately exercises untrappable SIGKILL both after worker publication and during the pre-exec publication window.

Coverage includes concurrent launcher serialization, reviewer/sync collection ownership, stale and zombie lock recovery, signal propagation, wrapper death, worker start gating, sync status/error/full-sync mappings, media abort ordering, timeout parsing and credential non-disclosure.

Full persisted log:

```text
docs/logs/KAP_CURRENT_HEAD_LIFECYCLE_SYNC_20260822.log
SHA-256 492c757b62cfaae0e729fe4249c4c74a9c937520e4c883084355a2818807edcb
```

Underlying final combined run log SHA-256:

```text
683ee3028487200a648dfdd9f7213531b5bcdf7603d9675262804da4268d8be9
```

## Remaining gates

Still required from one complete clean checkout are the remaining Python provenance/package/rootfs tests, `testenv` audio/launcher integration, official Anki 26.08.1 backend build and full tests, five real APKG integrations, fresh KindleHF ARMHF build/audit, retained-image-derived exact PW6 QEMU, package audit and separate physical HIL.

No release is claimed.
