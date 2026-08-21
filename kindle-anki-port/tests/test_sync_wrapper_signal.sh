#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kap-sync-signal.XXXXXX")
worker=
cleanup() {
    if [ -n "${worker:-}" ]; then
        kill -TERM "$worker" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM
APP="$TMP/app"
DATA="$TMP/data"
mkdir -p "$APP" "$DATA"
printf 'hkey=test-only\nendpoint=\n' >"$APP/config.ini"
printf 'collection' >"$DATA/collection.anki2"

cat >"$APP/kap-sync" <<'EOF_FAKE'
#!/usr/bin/env python3
import os
import signal

pid_path = os.environ["KAP_FAKE_CHILD_PID"]
trace_path = os.environ["KAP_FAKE_TRACE"]
with open(pid_path, "w", encoding="ascii") as handle:
    handle.write(str(os.getpid()) + "\n")
with open(trace_path, "a", encoding="ascii") as handle:
    handle.write("start\n")

def finish(signum, _frame):
    with open(trace_path, "a", encoding="ascii") as handle:
        handle.write("signal=%d\n" % signum)
    os._exit(128 + signum)

signal.signal(signal.SIGTERM, finish)
signal.signal(signal.SIGINT, finish)
signal.signal(signal.SIGHUP, finish)
if os.environ.get("KAP_FAKE_MODE") == "fail":
    os._exit(7)
while True:
    signal.pause()
EOF_FAKE
chmod 755 "$APP/kap-sync"

start_sync() {
    rm -f "$TMP/child.pid"
    KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" \
      KAP_FAKE_CHILD_PID="$TMP/child.pid" KAP_FAKE_TRACE="$TMP/trace" \
      "$ROOT/scripts/sync.sh" --interactive &
    wrapper=$!
    tries=0
    while [ ! -s "$TMP/child.pid" ]; do
        tries=$((tries + 1))
        test "$tries" -lt 200
        sleep 0.01
    done
    worker=$(cat "$TMP/child.pid")
    case "$worker" in ''|*[!0-9]*) echo "invalid worker pid: $worker" >&2; exit 1;; esac
}

# TERM to the wrapper must be forwarded to the real sync worker. The operation
# lock stays owned until the worker has stopped, then disappears.
start_sync
test "$(cat "$APP/.kap-operation.lock/pid")" = "$worker"
test "$(cat "$APP/.kap-operation.lock/mode")" = sync
kill -TERM "$wrapper"
set +e
wait "$wrapper"
status=$?
set -e
test "$status" = 143
tries=0
while kill -0 "$worker" 2>/dev/null; do
    tries=$((tries + 1))
    test "$tries" -lt 200
    sleep 0.01
done
worker=
test ! -d "$APP/.kap-operation.lock"
grep '^signal=15$' "$TMP/trace" >/dev/null

# Even an untrappable wrapper SIGKILL must not make the collection look free
# while the already-started sync worker is still alive: lock ownership is
# transferred to the worker PID before the wrapper waits.
start_sync
test "$(cat "$APP/.kap-operation.lock/pid")" = "$worker"
kill -KILL "$wrapper"
set +e
wait "$wrapper"
status=$?
set -e
test "$status" -ne 0
kill -0 "$worker" 2>/dev/null
test "$(cat "$APP/.kap-operation.lock/pid")" = "$worker"
test "$(cat "$APP/.kap-operation.lock/mode")" = sync
kill -TERM "$worker" 2>/dev/null || true
worker=
rm -f "$APP/.kap-operation.lock/pid" "$APP/.kap-operation.lock/mode"
rmdir "$APP/.kap-operation.lock"

# Backgrounding the worker for signal supervision must not mask its normal
# process exit status, and the lock must still be cleaned.
rm -f "$TMP/child.pid"
set +e
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_FAKE_MODE=fail \
  KAP_FAKE_CHILD_PID="$TMP/child.pid" KAP_FAKE_TRACE="$TMP/trace" \
  "$ROOT/scripts/sync.sh" --interactive
status=$?
set -e
test "$status" = 7
test ! -d "$APP/.kap-operation.lock"

echo "test_sync_wrapper_signal: ok"
