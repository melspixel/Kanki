#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CC=${CC:-cc}
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kap-life.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
APP="$TMP/app"
DATA="$TMP/data"
mkdir -p "$APP/scripts" "$DATA"
cp "$ROOT/scripts/launch.sh" "$APP/scripts/launch.sh"
cp "$ROOT/scripts/sync.sh" "$APP/scripts/sync.sh"
chmod 755 "$APP/scripts/"*.sh
$CC -O2 -std=c99 -Wall -Wextra -Werror "$ROOT/tests/fake_app.c" -o "$APP/kap-app"
cp "$APP/kap-app" "$APP/kap-sync"
printf '{"build_commit":"test-build"}\n' >"$APP/BUILD.json"
printf 'collection' >"$DATA/collection.anki2"
printf 'hkey=test-only\nendpoint=\n' >"$APP/config.ini"

KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_FAKE_MARKER="$TMP/ran" \
  "$APP/scripts/launch.sh"
test -f "$TMP/ran"
test ! -f "$APP/.kap.pid"
test ! -d "$APP/.kap-operation.lock"
test "$(find "$DATA/backups" -name 'collection-before-*.anki2' | wc -l | tr -d ' ')" = 1

KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_FAKE_MODE=wait-for-raise \
  KAP_FAKE_MARKER="$TMP/raised" "$APP/kap-app" &
resident=$!
printf '%s\n' "$resident" >"$APP/.kap.pid"
sleep 0.05
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" "$APP/scripts/launch.sh"
wait "$resident"
test -f "$TMP/raised"
test ! -d "$APP/.kap-operation.lock"

sleep 5 & foreign=$!
printf '%s\n' "$foreign" >"$APP/.kap.pid"
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_SYNC_BIN="$APP/kap-sync" \
  "$APP/scripts/sync.sh" --interactive
kill "$foreign" 2>/dev/null || true
wait "$foreign" 2>/dev/null || true

test ! -f "$APP/.kap.pid"
test ! -d "$APP/.kap-operation.lock"
test "$(find "$DATA/backups" -name 'collection-pre-sync-*.anki2' | wc -l | tr -d ' ')" = 1

rm -f "$APP/kap-sync"
set +e
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" "$APP/scripts/sync.sh" --interactive
status=$?
set -e
test "$status" = 69
test ! -d "$APP/.kap-operation.lock"

# Regression: two launchers used to race between the PID check and PID-file
# publication. Slow the pre-open backup so the old implementation reliably
# started two reviewer processes; the operation lock must keep this at one.
RACE_APP="$TMP/race-app"
RACE_DATA="$TMP/race-data"
FAKEBIN="$TMP/fakebin"
mkdir -p "$RACE_APP/scripts" "$RACE_DATA" "$FAKEBIN"
cp "$ROOT/scripts/launch.sh" "$RACE_APP/scripts/launch.sh"
cp "$ROOT/scripts/sync.sh" "$RACE_APP/scripts/sync.sh"
cp "$APP/kap-app" "$RACE_APP/kap-app"
printf '{"build_commit":"race-build"}\n' >"$RACE_APP/BUILD.json"
printf 'collection' >"$RACE_DATA/collection.anki2"
real_cp=$(command -v cp)
cat >"$FAKEBIN/cp" <<EOF_CP
#!/bin/sh
sleep 0.2
exec "$real_cp" "\$@"
EOF_CP
chmod 755 "$FAKEBIN/cp" "$RACE_APP/scripts/"*.sh
race_trace="$TMP/race.trace"
PATH="$FAKEBIN:$PATH" KAP_APP_DIR="$RACE_APP" KAP_DATA_DIR="$RACE_DATA" \
  KAP_FAKE_MODE=wait-for-raise KAP_FAKE_TRACE="$race_trace" \
  "$RACE_APP/scripts/launch.sh" & first_launcher=$!
PATH="$FAKEBIN:$PATH" KAP_APP_DIR="$RACE_APP" KAP_DATA_DIR="$RACE_DATA" \
  KAP_FAKE_MODE=wait-for-raise KAP_FAKE_TRACE="$race_trace" \
  "$RACE_APP/scripts/launch.sh" & second_launcher=$!
wait "$first_launcher" || true
wait "$second_launcher" || true
test "$(grep -c '^start ' "$race_trace")" = 1
test "$(grep -c '^raised ' "$race_trace")" = 1
test ! -d "$RACE_APP/.kap-operation.lock"
grep 'raised existing instance' "$RACE_APP/kindle-anki-port.log" >/dev/null

# Sync owns the same lock for its entire worker lifetime. A launch request while
# sync is active must fail closed rather than opening the collection concurrently.
LOCK_APP="$TMP/lock-app"
LOCK_DATA="$TMP/lock-data"
mkdir -p "$LOCK_APP/scripts" "$LOCK_DATA"
cp "$ROOT/scripts/launch.sh" "$LOCK_APP/scripts/launch.sh"
cp "$ROOT/scripts/sync.sh" "$LOCK_APP/scripts/sync.sh"
cp "$APP/kap-app" "$LOCK_APP/kap-app"
cp "$APP/kap-app" "$LOCK_APP/kap-sync"
chmod 755 "$LOCK_APP/scripts/"*.sh
printf '{"build_commit":"lock-build"}\n' >"$LOCK_APP/BUILD.json"
printf 'collection' >"$LOCK_DATA/collection.anki2"
printf 'hkey=test-only\nendpoint=\n' >"$LOCK_APP/config.ini"
lock_trace="$TMP/lock.trace"
KAP_APP_DIR="$LOCK_APP" KAP_DATA_DIR="$LOCK_DATA" KAP_FAKE_MODE=wait \
  KAP_FAKE_TRACE="$lock_trace" "$LOCK_APP/scripts/sync.sh" --interactive & sync_pid=$!
tries=0
while [ ! -f "$LOCK_APP/.kap-operation.lock/mode" ]; do
    tries=$((tries + 1))
    test "$tries" -lt 100
    sleep 0.02
done
test "$(cat "$LOCK_APP/.kap-operation.lock/mode")" = sync
set +e
KAP_APP_DIR="$LOCK_APP" KAP_DATA_DIR="$LOCK_DATA" "$LOCK_APP/scripts/launch.sh"
status=$?
set -e
test "$status" = 74
wait "$sync_pid"
test ! -d "$LOCK_APP/.kap-operation.lock"
grep 'launch refused while sync is running' "$LOCK_APP/kindle-anki-port.log" >/dev/null

# A dead lock owner must not permanently brick startup.
mkdir "$LOCK_APP/.kap-operation.lock"
printf '99999999\n' >"$LOCK_APP/.kap-operation.lock/pid"
printf 'launch\n' >"$LOCK_APP/.kap-operation.lock/mode"
KAP_APP_DIR="$LOCK_APP" KAP_DATA_DIR="$LOCK_DATA" KAP_FAKE_MARKER="$TMP/stale-lock-ran" \
  "$LOCK_APP/scripts/launch.sh"
test -f "$TMP/stale-lock-ran"
test ! -d "$LOCK_APP/.kap-operation.lock"

echo "test_lifecycle: ok"
