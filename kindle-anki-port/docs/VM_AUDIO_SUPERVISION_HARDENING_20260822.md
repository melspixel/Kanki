# VM audio-helper supervision hardening — 2026-08-22

## Defect

The native reviewer previously stopped its one-shot GStreamer helper with:

```c
kill(audio_pid, SIGTERM);
waitpid(audio_pid, NULL, 0);
```

That wait had no deadline. A helper blocked inside a Bluetooth/device-route transition, a firmware GStreamer call, or an unresponsive sink could therefore keep application cleanup blocked indefinitely. Collection close, PID/operation-lock cleanup, and a later launcher request would then be delayed or appear to fail. This is directly relevant to the reported leave-fullscreen/change-Bluetooth/re-enter failure mode.

The audio worker itself handles SIGTERM cooperatively, but process supervision must remain correct even when that cooperation fails.

## Repair

`native/app_part3.inc` now:

1. clears `app->audio_pid` before signaling so ownership cannot be reused recursively;
2. sends SIGTERM;
3. polls `waitpid(..., WNOHANG)` for a bounded 1000 ms grace period;
4. treats an already-reaped child as complete;
5. sends SIGKILL when the child is still alive;
6. synchronously reaps the force-killed child;
7. logs the forced-stop event without leaking user media or configuration.

`native/app_part4.inc` exposes:

```text
kap-app --self-test-audio-supervision
```

The self-test forks a child that deliberately ignores SIGTERM, synchronizes child readiness over a pipe, exercises the production `stop_audio()` path, then verifies:

- bounded return time;
- SIGKILL fallback;
- child reaping;
- cleared native ownership state.

The canonical static gate compiles the real native host and runs this self-test. `tests/test_source_contract.py` prevents removing the grace period, force-kill path, self-test entry point, or static-gate invocation without a failing test.

## Commits

```text
0acb54413bcddf3d16700f516dfaf213ebe31795  fix: bound audio-helper shutdown before app cleanup
7456f953296970a96d4bc2dd39e5fcd8e441bc28  test: expose bounded audio-shutdown self-test
e1460fff9830cc19a1f6ce8e083cc5c248d74328  test: gate bounded audio-helper shutdown
1a4a1744ec7e50efaa212d170de549e71d671f23  test: enforce bounded native audio supervision contract
```

## Targeted evidence

Both a standalone strict-C harness and a full native translation-unit checkpoint compile used:

```text
-O2 -std=c99 -Wall -Wextra -Werror
```

Observed result:

```text
audio pid=<pid> did not stop after 1000ms; forcing SIGKILL
kap-app audio supervision self-test: ok elapsed_ms=1002
status=0
```

Persisted raw evidence:

```text
docs/logs/KAP_AUDIO_SUPERVISION_TARGETED_20260822.log
```

The log records source/binary/log hashes and the precise scope of each targeted compile.

## Evidence boundary

This checkpoint does **not** claim the full current-head static suite, ARMHF rebuild, exact-rootfs QEMU run, or physical Bluetooth acceptance. The isolated execution container still lacks a complete clean live-branch worktree and normal GitHub DNS access. The next clean current-head build must compile the canonical fragmented `native/app.c`, execute the newly wired self-test, rebuild ARMHF, and carry the resulting source identity into QEMU/package provenance.

Physical acceptance must still verify that real `mixersink` playback can be interrupted during Bluetooth route changes and that the application closes and re-enters without requiring a Kindle reboot.
