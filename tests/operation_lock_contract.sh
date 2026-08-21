#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/kanki-operation-lock.XXXXXX)
LOCK_ROOT="$WORK/kanki"
HELPER="$ROOT/scripts/kanki-operation-lock.sh"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'collection operation lock contract: FAIL: %s\n' "$*" >&2
    exit 1
}

expect_busy() {
    if sh -c '
        exec 9>&-
        . "$KANKI_LOCK_HELPER"
        kanki_operation_lock_acquire sync
    '; then
        fail 'a second open-file description acquired the live lock'
    else
        STATUS=$?
    fi
    [ "$STATUS" -eq 74 ] ||
        fail "live lock returned status $STATUS instead of 74"
}

mkdir "$LOCK_ROOT"
printf '%s\n' 'host contract operation lock' \
    >"$LOCK_ROOT/.kanki.operation.lock"
cc -std=c11 -Wall -Wextra -Werror "$ROOT/tests/flock_fd.c" \
    -o "$WORK/flock"

export KANKI_OPERATION_ROOT=$LOCK_ROOT
export KANKI_OPERATION_LOCK_FILE="$LOCK_ROOT/.kanki.operation.lock"
export KANKI_OPERATION_STATE_DIR="$LOCK_ROOT/.kanki.lock"
export KANKI_FLOCK="$WORK/flock"
export KANKI_LOCK_HELPER=$HELPER

. "$HELPER"
kanki_operation_lock_acquire launch ||
    fail 'initial launcher lock acquisition failed'
[ "$(cat "$KANKI_OPERATION_STATE_DIR/pid")" = "$$" ] ||
    fail 'launcher owner metadata does not name the holder'
[ "$(cat "$KANKI_OPERATION_STATE_DIR/mode")" = launch ] ||
    fail 'launcher mode metadata is missing'

expect_busy

KANKI_EXPECTED_OWNER=$$
export KANKI_EXPECTED_OWNER
if ! sh -c '
    . "$KANKI_LOCK_HELPER"
    kanki_operation_lock_validate_inherited "$KANKI_EXPECTED_OWNER" launch
'; then
    fail 'launcher child could not validate the inherited descriptor lock'
fi

# A collection worker inherits descriptor 9. If its wrapper is killed or
# closes its descriptor, the kernel lock remains live until the worker exits.
sleep 1 &
WORKER_PID=$!
exec 9>&-
KANKI_OPERATION_LOCK_HELD=0
expect_busy
wait "$WORKER_PID"

if ! sh -c '
    exec 9>&-
    . "$KANKI_LOCK_HELPER"
    kanki_operation_lock_acquire sync
    kanki_operation_lock_cleanup
'; then
    fail 'lock did not recover automatically after the inherited worker exited'
fi
[ ! -d "$KANKI_OPERATION_STATE_DIR" ] ||
    fail 'normal owner-aware cleanup left operation metadata behind'

printf '%s\n' 'collection operation lock contract: pass'
