#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BUILD=${KAP_SYNC_TEST_BUILD:-$ROOT/build/sync-worker-test}
CC=${CC:-cc}
mkdir -p "$BUILD"

$CC -O2 -std=c99 -Wall -Wextra -Werror -fPIC -shared -I"$ROOT/core" \
    "$ROOT/tests/fake_sync_backend.c" -o "$BUILD/libfake-kap-sync.so"
$CC -O2 -std=c99 -Wall -Wextra -Werror -I"$ROOT/core" \
    "$ROOT/native/sync.c" -ldl -o "$BUILD/kap-sync"

run_case() {
    name=$1 expected=$2 required=$3
    shift 3
    log="$BUILD/$name.log"
    set +e
    KAP_SYNC_HKEY=fixture-secret KAP_FAKE_SYNC_REQUIRED="$required" \
      "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
      --collection "$BUILD/collection.anki2" --media "$BUILD/media" \
      --media-db "$BUILD/media.db2" "$@" >"$log" 2>&1
    status=$?
    set -e
    [ "$status" -eq "$expected" ] || {
      echo "$name: expected status $expected, got $status" >&2
      cat "$log" >&2
      exit 1
    }
    if grep -q 'fixture-secret' "$log"; then
      echo "$name: sync credential leaked to output" >&2
      exit 1
    fi
}

run_case no_changes 0 0 --no-media
run_case full_sync_required 75 2 --no-media
run_case download_required 76 3 --no-media
run_case upload_required 77 4 --no-media
run_case full_upload 0 0 --full-upload --server-usn 17
run_case full_download 0 0 --full-download --server-usn 17
KAP_FAKE_MEDIA_ACTIVE_ONCE=1 run_case media_poll 0 0

set +e
env -u KAP_SYNC_HKEY "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z >"$BUILD/missing-hkey.log" 2>&1
status=$?
set -e
[ "$status" -eq 64 ] || { echo "missing hkey: expected 64, got $status" >&2; exit 1; }

echo "test_sync_worker: ok"
