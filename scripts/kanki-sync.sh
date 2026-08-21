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

if [ -f "$DIR/MANIFEST.sha256" ]; then
    (cd "$DIR" && sha256sum -c MANIFEST.sha256) >>"$LOG" 2>&1 || exit 71
fi

chmod 755 "$DIR/kanki-sync" 2>/dev/null || true
"$DIR/kanki-sync" "$@" >>"$LOG" 2>&1
