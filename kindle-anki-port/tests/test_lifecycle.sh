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
test "$(find "$DATA/backups" -name 'collection-before-*.anki2' | wc -l | tr -d ' ')" = 1

KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_FAKE_MODE=wait-for-raise \
  KAP_FAKE_MARKER="$TMP/raised" "$APP/kap-app" &
resident=$!
printf '%s\n' "$resident" >"$APP/.kap.pid"
sleep 0.05
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" "$APP/scripts/launch.sh"
wait "$resident"
test -f "$TMP/raised"

sleep 5 & foreign=$!
printf '%s\n' "$foreign" >"$APP/.kap.pid"
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" KAP_SYNC_BIN="$APP/kap-sync" \
  "$APP/scripts/sync.sh" --interactive
kill "$foreign" 2>/dev/null || true
wait "$foreign" 2>/dev/null || true

test ! -f "$APP/.kap.pid"
test "$(find "$DATA/backups" -name 'collection-pre-sync-*.anki2' | wc -l | tr -d ' ')" = 1

rm -f "$APP/kap-sync"
set +e
KAP_APP_DIR="$APP" KAP_DATA_DIR="$DATA" "$APP/scripts/sync.sh" --interactive
status=$?
set -e
test "$status" = 69

echo "test_lifecycle: ok"
