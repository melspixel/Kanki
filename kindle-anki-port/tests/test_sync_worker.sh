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

assert_trace() {
    name=$1 expected=$2
    actual=$(tr '\n' '|' <"$BUILD/$name.trace" | sed 's/|$//')
    [ "$actual" = "$expected" ] || {
        echo "$name: trace mismatch" >&2
        echo "expected: $expected" >&2
        echo "actual:   $actual" >&2
        exit 1
    }
}

assert_trace_contains() {
    name=$1 needle=$2
    grep -F -- "$needle" "$BUILD/$name.trace" >/dev/null || {
        echo "$name: trace missing: $needle" >&2
        cat "$BUILD/$name.trace" >&2
        exit 1
    }
}

run_case() {
    name=$1 expected=$2 required=$3
    shift 3
    log="$BUILD/$name.log"
    trace="$BUILD/$name.trace"
    rm -f "$log" "$trace"
    set +e
    KAP_SYNC_HKEY=fixture-secret KAP_FAKE_SYNC_REQUIRED="$required" KAP_FAKE_TRACE="$trace" \
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
    if grep -q 'fixture-secret' "$log" "$trace" 2>/dev/null; then
      echo "$name: sync credential leaked to output/trace" >&2
      exit 1
    fi
}

run_case no_changes 0 0 --no-media
assert_trace no_changes 'core_new|open|sync endpoint= flag=0 server_usn=0 has_server_usn=0 timeout=120|close|core_free'

run_case endpoint_timeout 0 0 --no-media --timeout 9
KAP_SYNC_ENDPOINT=https://sync.fixture.invalid run_case endpoint_value 0 0 --no-media --timeout 7
assert_trace_contains endpoint_timeout 'sync endpoint= flag=0 server_usn=0 has_server_usn=0 timeout=9'
assert_trace_contains endpoint_value 'sync endpoint=https://sync.fixture.invalid flag=0 server_usn=0 has_server_usn=0 timeout=7'

run_case full_sync_required 75 2 --no-media
run_case download_required 76 3 --no-media
run_case upload_required 77 4 --no-media
run_case unknown_required 78 99 --no-media

run_case full_upload 0 0 --full-upload --server-usn 17 --no-media --timeout 8
assert_trace_contains full_upload 'full endpoint= flag=1 server_usn=17 has_server_usn=1 timeout=8'
run_case full_download 0 0 --full-download --server-usn -17 --no-media --timeout 6
assert_trace_contains full_download 'full endpoint= flag=0 server_usn=-17 has_server_usn=1 timeout=6'

KAP_FAKE_MEDIA_ACTIVE_ONCE=1 run_case media_poll 0 0
assert_trace media_poll 'core_new|open|sync endpoint= flag=1 server_usn=0 has_server_usn=0 timeout=120|media_status|media_status|close|core_free'

KAP_FAKE_SYNC_FAIL=1 run_case sync_error 1 0 --no-media
assert_trace sync_error 'core_new|open|sync endpoint= flag=0 server_usn=0 has_server_usn=0 timeout=120|close|core_free'
KAP_FAKE_OPEN_FAIL=1 run_case open_error 68 0 --no-media
assert_trace open_error 'core_new|open|close|core_free'
KAP_FAKE_FULL_SYNC_FAIL=1 run_case full_sync_error 1 0 --full-upload --server-usn 17 --no-media
assert_trace full_sync_error 'core_new|open|full endpoint= flag=1 server_usn=17 has_server_usn=1 timeout=120|close|core_free'
KAP_FAKE_MEDIA_FAIL=1 run_case media_error 1 0
assert_trace media_error 'core_new|open|sync endpoint= flag=1 server_usn=0 has_server_usn=0 timeout=120|media_status|close|core_free'

# A blocked media poll must respond to SIGTERM by calling abort, then close/free.
abort_log="$BUILD/signal_abort.log"
abort_trace="$BUILD/signal_abort.trace"
rm -f "$abort_log" "$abort_trace"
set +e
KAP_SYNC_HKEY=fixture-secret KAP_FAKE_SYNC_REQUIRED=0 \
KAP_FAKE_MEDIA_ACTIVE_FOREVER=1 KAP_FAKE_TRACE="$abort_trace" \
  "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection "$BUILD/collection.anki2" --media "$BUILD/media" \
  --media-db "$BUILD/media.db2" >"$abort_log" 2>&1 &
pid=$!
set -e
count=0
while ! grep -q '^media_status$' "$abort_trace" 2>/dev/null; do
    count=$((count + 1))
    if [ "$count" -gt 100 ]; then
        echo "signal_abort: media wait did not start" >&2
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        exit 1
    fi
    sleep 0.02
done
kill -TERM "$pid"
set +e
wait "$pid"
status=$?
set -e
[ "$status" -eq 130 ] || { echo "signal_abort: expected 130, got $status" >&2; cat "$abort_log" >&2; exit 1; }
assert_trace_contains signal_abort 'abort'
# Order matters for shutdown: abort must precede close, and close must precede free.
awk 'BEGIN{a=0;c=0;f=0} /^abort$/{a=NR} /^close$/{c=NR} /^core_free$/{f=NR} END{exit !(a && c>a && f>c)}' "$abort_trace" || {
    echo "signal_abort: shutdown order invalid" >&2
    cat "$abort_trace" >&2
    exit 1
}

set +e
env -u KAP_SYNC_HKEY "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z >"$BUILD/missing-hkey.log" 2>&1
status=$?
set -e
[ "$status" -eq 64 ] || { echo "missing hkey: expected 64, got $status" >&2; exit 1; }

set +e
KAP_SYNC_HKEY='' "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z >"$BUILD/empty-hkey.log" 2>&1
status=$?
set -e
[ "$status" -eq 64 ] || { echo "empty hkey: expected 64, got $status" >&2; exit 1; }

set +e
KAP_SYNC_HKEY=fixture-secret "$BUILD/kap-sync" --backend "$BUILD/does-not-exist.so" \
  --collection x --media y --media-db z >"$BUILD/dlopen-fail.log" 2>&1
status=$?
set -e
[ "$status" -eq 65 ] || { echo "dlopen failure: expected 65, got $status" >&2; exit 1; }

set +e
KAP_SYNC_HKEY=fixture-secret KAP_FAKE_CORE_NEW_FAIL=1 KAP_FAKE_TRACE="$BUILD/core-new-fail.trace" \
  "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z >"$BUILD/core-new-fail.log" 2>&1
status=$?
set -e
[ "$status" -eq 67 ] || { echo "core new failure: expected 67, got $status" >&2; exit 1; }
if grep -q 'fixture-secret' "$BUILD/core-new-fail.log"; then
    echo "core new failure leaked credential" >&2
    exit 1
fi

set +e
KAP_SYNC_HKEY=fixture-secret "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z --full-upload --full-download >"$BUILD/conflicting-full.log" 2>&1
status=$?
set -e
[ "$status" -eq 64 ] || { echo "conflicting full sync modes: expected 64, got $status" >&2; exit 1; }

set +e
KAP_SYNC_HKEY=fixture-secret "$BUILD/kap-sync" --backend "$BUILD/libfake-kap-sync.so" \
  --collection x --media y --media-db z --timeout 4294967296 >"$BUILD/timeout-overflow.log" 2>&1
status=$?
set -e
[ "$status" -eq 64 ] || { echo "timeout overflow: expected 64, got $status" >&2; exit 1; }

echo "test_sync_worker: ok"
