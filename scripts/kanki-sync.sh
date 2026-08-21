#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
LOCK="$DIR/.kanki.lock"
CONFIG="$DIR/config.ini"
OLD_CONFIG=/mnt/us/extensions/ranki/config.ini

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

# External syncs must never race the reviewer. The launcher owns the same lock
# while performing an in-process handoff: the reviewer has exited and closed
# the collection, but the launcher PID deliberately remains the lock owner so
# a second Kanki launch cannot enter during sync.
if [ -d "$LOCK" ] && [ "${KANKI_SYNC_FROM_LAUNCHER:-0}" != "1" ]; then
    printf '%s sync refused while Kanki is running\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
    exit 74
fi
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
"$DIR/kanki-sync" "$@" >>"$LOG" 2>&1
