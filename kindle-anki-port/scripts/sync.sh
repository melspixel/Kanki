#!/bin/sh
set -eu

APP=${KAP_APP_DIR:-/mnt/us/extensions/kindle-anki-port}
DATA=${KAP_DATA_DIR:-/mnt/us/anki_data}
LOG=${KAP_LOG_FILE:-$APP/kindle-anki-port.log}
CONFIG=${KAP_CONFIG_FILE:-$APP/config.ini}
PID_FILE=${KAP_PID_FILE:-$APP/.kap.pid}
APP_BIN=${KAP_APP_BIN:-$APP/kap-app}
SYNC_BIN=${KAP_SYNC_BIN:-$APP/kap-sync}

mkdir -p "$APP" "$DATA" "$DATA/backups"
umask 077

log() {
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$LOG"
}

canonical_path() {
    target=$1
    if command -v readlink >/dev/null 2>&1; then
        resolved=$(readlink -f "$target" 2>/dev/null || true)
        [ -n "$resolved" ] && { printf '%s\n' "$resolved"; return 0; }
    fi
    printf '%s\n' "$target"
}

verified_app_pid() {
    pid=$1
    [ -n "$pid" ] || return 1
    case "$pid" in *[!0-9]*) return 1;; esac
    kill -0 "$pid" 2>/dev/null || return 1
    exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
    [ "$exe" = "$(canonical_path "$APP_BIN")" ]
}

if [ -f "$PID_FILE" ]; then
    pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if verified_app_pid "$pid"; then
        log "sync refused while reviewer is running pid=$pid"
        exit 74
    fi
    rm -f "$PID_FILE"
    log "removed stale or foreign pid before sync"
fi

if [ ! -x "$SYNC_BIN" ]; then
    log "sync executable is missing or not executable: $SYNC_BIN"
    exit 69
fi

if [ ! -r "$CONFIG" ]; then
    log "missing $CONFIG"
    exit 78
fi

hkey=$(sed -n 's/^[[:space:]]*hkey[[:space:]]*=[[:space:]]*//p' "$CONFIG" | tail -1)
endpoint=$(sed -n 's/^[[:space:]]*endpoint[[:space:]]*=[[:space:]]*//p' "$CONFIG" | tail -1)
[ -n "$hkey" ] || { log "missing hkey in $CONFIG"; exit 78; }

backup="$DATA/backups/collection-pre-sync-$(date '+%Y%m%d-%H%M%S').anki2"
[ -f "$DATA/collection.anki2" ] && cp -p "$DATA/collection.anki2" "$backup"
find "$DATA/backups" -type f -name 'collection-pre-sync-*.anki2' -print \
    | sort -r | awk 'NR>5' | while IFS= read -r old; do rm -f "$old"; done

KAP_SYNC_HKEY="$hkey" KAP_SYNC_ENDPOINT="$endpoint" \
    "$SYNC_BIN" --backend "$APP/libanki-kindle.so" \
    --collection "$DATA/collection.anki2" \
    --media "$DATA/collection.media" --media-db "$DATA/media.db2" "$@"

unset hkey endpoint
