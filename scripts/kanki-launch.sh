#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
LOCK="$DIR/.kanki.lock"

mkdir -p "$DIR"
if ! mkdir "$LOCK" 2>/dev/null; then
    PID=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        printf '%s duplicate launch ignored pid=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PID" >>"$LOG"
        exit 0
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK"
fi
printf '%s\n' "$$" >"$LOCK/pid"
cleanup() { rm -rf "$LOCK"; }
trap cleanup EXIT INT TERM

if [ -f "$DIR/MANIFEST.sha256" ]; then
    (cd "$DIR" && sha256sum -c MANIFEST.sha256) >>"$LOG" 2>&1 || {
        printf '%s manifest verification failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
        exit 71
    }
fi

chmod 755 "$DIR/kanki-device" 2>/dev/null || true
exec "$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" >>"$LOG" 2>&1
