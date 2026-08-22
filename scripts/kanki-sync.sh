#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
KANKI_OPERATION_ROOT=$DIR
KANKI_OPERATION_LOCK_FILE="$DIR/.kanki.operation.lock"
KANKI_OPERATION_STATE_DIR="$DIR/.kanki.lock"
KANKI_FLOCK=/usr/bin/flock
CONFIG="$DIR/config.ini"
OLD_CONFIG=/mnt/us/extensions/ranki/config.ini
SYNC_PID=

if [ ! -f "$DIR/BUILD.json" ] || [ -L "$DIR/BUILD.json" ] || \
    [ ! -f "$DIR/MANIFEST.sha256" ] || [ -L "$DIR/MANIFEST.sha256" ]; then
    printf '%s sync refused: build identity or package manifest missing/symbolic\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 70
fi
if [ ! -f "$DIR/kanki-verify.sh" ] || [ -L "$DIR/kanki-verify.sh" ]; then
    printf '%s sync refused: install verifier missing or symbolic\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 71
fi
VERIFY_RECORD=$(grep -E '^[0-9a-fA-F]{64}  \./kanki-verify\.sh$' \
    "$DIR/MANIFEST.sha256" 2>/dev/null || true)
if [ -z "$VERIFY_RECORD" ] || \
    ! printf '%s\n' "$VERIFY_RECORD" | (cd "$DIR" && sha256sum -c -) \
        >/dev/null 2>&1; then
    printf '%s sync refused: install verifier mismatched\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 71
fi
if sh "$DIR/kanki-verify.sh" "$DIR" >/dev/null; then
    :
else
    STATUS=$?
    printf '%s sync refused: installation integrity verification failed status=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "$STATUS" >&2
    exit "$STATUS"
fi

umask 077
if [ ! -f "$DIR/kanki-operation-lock.sh" ] ||
    [ -L "$DIR/kanki-operation-lock.sh" ]; then
    printf '%s sync refused: collection operation lock helper missing or symbolic\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 73
fi
. "$DIR/kanki-operation-lock.sh"

# A launcher-initiated sync inherits descriptor 9 from the launcher and must
# prove both its exact manifest-owned file and launcher owner record. A
# standalone sync atomically acquires the same kernel lock before any process
# can open the collection. Merely checking for a lock path is a TOCTOU race.
if [ -n "${KANKI_OPERATION_LOCK_OWNER:-}" ]; then
    if kanki_operation_lock_validate_inherited \
        "$KANKI_OPERATION_LOCK_OWNER" launch; then
        :
    else
        STATUS=$?
        printf '%s sync refused: invalid launcher lock inheritance status=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$STATUS" >>"$LOG"
        exit "$STATUS"
    fi
else
    if kanki_operation_lock_acquire sync; then
        :
    else
        STATUS=$?
        BUSY_MODE=$(cat "$KANKI_OPERATION_STATE_DIR/mode" 2>/dev/null || true)
        BUSY_PID=$(cat "$KANKI_OPERATION_STATE_DIR/pid" 2>/dev/null || true)
        printf '%s sync refused: collection operation busy mode=%s owner=%s status=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "${BUSY_MODE:-unknown}" \
            "${BUSY_PID:-unknown}" "$STATUS" >>"$LOG"
        exit "$STATUS"
    fi
fi

cleanup_sync() {
    kanki_operation_lock_cleanup
}

forward_signal() {
    SIGNAL_NAME=$1
    SIGNAL_NUMBER=$2
    trap - HUP INT TERM
    if [ -n "${SYNC_PID:-}" ] && kill -0 "$SYNC_PID" 2>/dev/null; then
        kill -"$SIGNAL_NAME" "$SYNC_PID" 2>/dev/null || true
        wait "$SYNC_PID" 2>/dev/null || true
    fi
    SYNC_PID=
    exit $((128 + SIGNAL_NUMBER))
}

trap cleanup_sync EXIT
trap 'forward_signal HUP 1' HUP
trap 'forward_signal INT 2' INT
trap 'forward_signal TERM 15' TERM

printf '%s installation integrity verification passed before sync\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"

if [ ! -f "$CONFIG" ] && [ -r "$OLD_CONFIG" ]; then
    HKEY=$(sed -n 's/^[[:space:]]*hkey[[:space:]]*=[[:space:]]*//p' "$OLD_CONFIG" | tail -n 1)
    ENDPOINT=$(sed -n 's/^[[:space:]]*endpoint[[:space:]]*=[[:space:]]*//p' "$OLD_CONFIG" | tail -n 1)
    if [ -n "$HKEY" ]; then
        umask 077
        {
            printf 'hkey=%s\n' "$HKEY"
            printf 'endpoint=%s\n' "$ENDPOINT"
        } >"$CONFIG"
    fi
    unset HKEY ENDPOINT
fi

chmod 755 "$DIR/kanki-sync" 2>/dev/null || true
"$DIR/kanki-sync" "$@" >>"$LOG" 2>&1 &
SYNC_PID=$!
if wait "$SYNC_PID"; then
    STATUS=0
else
    STATUS=$?
fi
SYNC_PID=
exit "$STATUS"
