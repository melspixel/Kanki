#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
LOCK="$DIR/.kanki.lock"
CONFIG="$DIR/config.ini"
OLD_CONFIG=/mnt/us/extensions/ranki/config.ini

# External syncs must never race the reviewer. The launcher owns the same lock
# while performing an in-process handoff: the reviewer has exited and closed
# the collection, but the launcher PID deliberately remains the lock owner so
# a second Kanki launch cannot enter during sync.
if [ -d "$LOCK" ] && [ "${KANKI_SYNC_FROM_LAUNCHER:-0}" != "1" ]; then
    printf '%s sync refused while Kanki is running\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
    exit 74
fi

if [ ! -r "$DIR/BUILD.json" ] || [ ! -r "$DIR/MANIFEST.sha256" ]; then
    printf '%s sync refused: build identity or package manifest missing\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
    exit 70
fi
(cd "$DIR" && sha256sum -c MANIFEST.sha256) >>"$LOG" 2>&1 || {
    printf '%s sync refused: package manifest verification failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
    exit 71
}

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
