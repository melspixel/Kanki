#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kap-zombie-lock.XXXXXX")
zombie_parent=
zombie_release=
cleanup() {
    if [ -n "${zombie_release:-}" ]; then
        : >"$zombie_release" 2>/dev/null || true
    fi
    if [ -n "${zombie_parent:-}" ]; then
        wait "$zombie_parent" 2>/dev/null || true
    fi
    rm -rf "$TMP"
}
trap cleanup EXIT HUP INT TERM

make_zombie() {
    pid_file=$1
    zombie_release=$2
    rm -f "$pid_file" "$zombie_release"
    python3 - "$pid_file" "$zombie_release" <<'PY' &
import os
import sys
import time

pid_file, release_file = sys.argv[1:]
child = os.fork()
if child == 0:
    os._exit(0)
with open(pid_file, "w", encoding="ascii") as handle:
    handle.write(str(child) + "\n")
while not os.path.exists(release_file):
    time.sleep(0.01)
os.waitpid(child, 0)
PY
    zombie_parent=$!
    tries=0
    while [ ! -s "$pid_file" ]; do
        tries=$((tries + 1))
        test "$tries" -lt 200
        sleep 0.01
    done
    zombie_pid=$(cat "$pid_file")
    tries=0
    while :; do
        stat_line=$(cat "/proc/$zombie_pid/stat" 2>/dev/null || true)
        case "$stat_line" in
            *') Z '*) break ;;
        esac
        tries=$((tries + 1))
        test "$tries" -lt 200
        sleep 0.01
    done
}

reap_zombie() {
    : >"$zombie_release"
    wait "$zombie_parent"
    zombie_parent=
    zombie_release=
}

# A zombie sync owner still answers kill -0, but it cannot own the collection.
# The launcher must recognize the /proc state and reclaim that stale lock.
LAUNCH_APP="$TMP/launch-app"
LAUNCH_DATA="$TMP/launch-data"
mkdir -p "$LAUNCH_APP/scripts" "$LAUNCH_DATA"
cp "$ROOT/scripts/launch.sh" "$LAUNCH_APP/scripts/launch.sh"
chmod 755 "$LAUNCH_APP/scripts/launch.sh"
cat >"$LAUNCH_APP/kap-app" <<'EOF_APP'
#!/bin/sh
: >"$KAP_FAKE_MARKER"
exit 0
EOF_APP
chmod 755 "$LAUNCH_APP/kap-app"
printf '{"build_commit":"zombie-lock-test"}\n' >"$LAUNCH_APP/BUILD.json"
printf 'collection' >"$LAUNCH_DATA/collection.anki2"
make_zombie "$TMP/launch-zombie.pid" "$TMP/launch-zombie.release"
mkdir "$LAUNCH_APP/.kap-operation.lock"
printf '%s\n' "$zombie_pid" >"$LAUNCH_APP/.kap-operation.lock/pid"
printf 'sync\n' >"$LAUNCH_APP/.kap-operation.lock/mode"
kill -0 "$zombie_pid" 2>/dev/null
KAP_APP_DIR="$LAUNCH_APP" KAP_DATA_DIR="$LAUNCH_DATA" \
  KAP_FAKE_MARKER="$TMP/launch-ran" "$LAUNCH_APP/scripts/launch.sh"
test -f "$TMP/launch-ran"
test ! -d "$LAUNCH_APP/.kap-operation.lock"
reap_zombie

# The sync wrapper must make the same distinction. This covers the exact stale
# state produced when a gated pre-exec worker exits after its wrapper is killed.
SYNC_APP="$TMP/sync-app"
SYNC_DATA="$TMP/sync-data"
mkdir -p "$SYNC_APP/scripts" "$SYNC_DATA"
cp "$ROOT/scripts/sync.sh" "$SYNC_APP/scripts/sync.sh"
chmod 755 "$SYNC_APP/scripts/sync.sh"
cat >"$SYNC_APP/kap-sync" <<'EOF_SYNC'
#!/bin/sh
exit 7
EOF_SYNC
chmod 755 "$SYNC_APP/kap-sync"
printf 'hkey=test-only\nendpoint=\n' >"$SYNC_APP/config.ini"
printf 'collection' >"$SYNC_DATA/collection.anki2"
make_zombie "$TMP/sync-zombie.pid" "$TMP/sync-zombie.release"
mkdir "$SYNC_APP/.kap-operation.lock"
printf '%s\n' "$zombie_pid" >"$SYNC_APP/.kap-operation.lock/pid"
printf 'sync\n' >"$SYNC_APP/.kap-operation.lock/mode"
kill -0 "$zombie_pid" 2>/dev/null
set +e
KAP_APP_DIR="$SYNC_APP" KAP_DATA_DIR="$SYNC_DATA" \
  "$SYNC_APP/scripts/sync.sh" --interactive
status=$?
set -e
test "$status" = 7
test ! -d "$SYNC_APP/.kap-operation.lock"
reap_zombie

echo "test_zombie_operation_lock: ok"
