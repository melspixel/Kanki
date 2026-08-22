# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22 UTC

## Current state

VM-side continuation remains active. GitHub Actions quota exhaustion is not treated as a compiler blocker, and ordinary compilation is not delegated to the user's host.

Persisted historical green checkpoints include:

```text
official Anki rslib             539/539
five real APKG C-ABI flows      PASS
reviewer runtime fixtures       PASS
sync/lifecycle fixtures         PASS
ARMHF hard-float build          PASS
ABI/GLIBC audit                 PASS
QEMU static ARM sanity          PASS
```

Those checkpoints predate the current release-provenance and lifecycle hardening. A complete clean-current-head rerun remains mandatory before release.

## Latest material advances

### 1. Bounded audio-helper shutdown

A native lifecycle defect was found in the production host: `stop_audio()` sent SIGTERM and then used an unbounded blocking `waitpid()`. A GStreamer helper wedged during a Bluetooth/device-route transition could therefore pin application cleanup, delay collection close, and make a later launcher request appear to crash or remain a duplicate instance.

The native host now:

```text
clears audio_pid ownership
-> SIGTERM
-> bounded WNOHANG reap for 1000 ms
-> SIGKILL fallback
-> mandatory final reap
```

The real native binary exposes:

```text
kap-app --self-test-audio-supervision
```

The canonical static gate compiles the host and executes that regression. The self-test creates a child that deliberately ignores SIGTERM and verifies bounded forced cleanup.

Targeted strict-C and full translation-unit checkpoint evidence:

```text
audio pid=<pid> did not stop after 1000ms; forcing SIGKILL
kap-app audio supervision self-test: ok elapsed_ms=1002
status=0
```

Commits:

```text
0acb54413bcddf3d16700f516dfaf213ebe31795  bound audio-helper shutdown
7456f953296970a96d4bc2dd39e5fcd8e441bc28  expose native supervision self-test
e1460fff9830cc19a1f6ce8e083cc5c248d74328  wire self-test into static gate
1a4a1744ec7e50efaa212d170de549e71d671f23  lock source/static contract
```

Evidence:

```text
docs/VM_AUDIO_SUPERVISION_HARDENING_20260822.md
docs/logs/KAP_AUDIO_SUPERVISION_TARGETED_20260822.log
```

This is targeted evidence only. Real Bluetooth route switching remains a physical PW6 gate.

### 2. Clean-checkout shell-entrypoint portability

Two shell regression fixtures were committed without the executable bit while the static gate invoked them directly. A developer worktree with repaired modes could pass while a clean archive failed before executing tests.

The gate now uses:

```text
sh tests/test_sync_wrapper_signal.sh
sh tests/test_sync_worker.sh
```

and `tests/test_build_entrypoints.py` locks that contract.

Commits:

```text
9d68dd5bb72dfc16d3ab2f06e3c0b7405492f157
163cc8575bf8952ecc0adbaf7201ce2bf1821ac0
```

Evidence: `docs/logs/KAP_SHELL_ENTRYPOINT_TARGETED_20260822.log`.

### 3. Existing lifecycle and sync hardening

The continuation previously reproduced and fixed:

- concurrent-launch PID publication race;
- reviewer/sync collection-open overlap;
- sync-wrapper death leaving an unprotected worker;
- zombie operation-lock owners;
- stale-lock cleanup and ownership-aware release;
- conflicting full-sync direction and sync error propagation;
- packaging of transient/user state.

Detailed evidence remains in:

```text
docs/VM_CONTINUATION_20260822.md
docs/VM_LIFECYCLE_HARDENING_20260822.md
docs/VM_ZOMBIE_LOCK_HARDENING_20260822.md
docs/VM_PACKAGE_HARDENING_20260822.md
```

### 4. Source/build/runtime provenance hardening

Current release gates require:

```text
resolvable clean project HEAD^{commit}
+ exact pinned Anki HEAD^{commit}
+ deterministic allowed Anki overlay only
+ fresh gate-owned Cargo target
+ fresh ARMHF output
+ retained-image-bound exact PW6 QEMU
+ QEMU-bound package audit
```

A stale binary, copied target directory, non-Git source tree, unrelated dirty Anki source, caller-supplied rootfs directory, or package-before-QEMU path cannot claim release provenance.

## Active blockers / next execution targets

1. Materialize a complete clean copy of the latest canonical branch head in a network-capable build VM.
2. Run the full static gate, now including shell portability and bounded audio supervision.
3. Rerun official Anki tests and all five real APKG integrations from that exact source/Anki identity.
4. Rebuild ARMHF and repeat ELF/ABI/GLIBC/export audit.
5. Supply both exact private PW6 inputs:
   - extracted checksum-verified rootfs;
   - retained `pw6-rootfs.img` with SHA-256 `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`.
6. Run image-derived exact-rootfs QEMU.
7. Only then assemble and persist the final installer and complete reports on GitHub.
8. Run physical PW6 HIL separately.

The isolated execution container still cannot resolve `github.com` through normal DNS, does not contain the complete live branch worktree, and does not have the private rootfs/image pair. These limitations do not justify weakening the gates or moving ordinary compilation to the user's host.

## Persistence rule

`HANDOFF.md` is the authoritative continuation point; `PROGRESS.md` is the phase matrix. Every material source/test/build change is synchronized to the `kindle-anki-port` branch. Temporary VM files and historical ZIPs are checkpoints only, never releases.

## User involvement

No local-host compilation action is currently requested. `CODEX_COORDINATION.md` contains the narrow private-rootfs transport task. Physical PW6 work starts only after final software-release hashes exist.
