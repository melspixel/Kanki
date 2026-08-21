#!/bin/sh
set -eu

APP=${KAP_APP_DIR:-/mnt/us/extensions/kindle-anki-port}
DATA=${KAP_DATA_DIR:-/mnt/us/anki_data}
BIN=${KAP_APP_BIN:-$APP/kap-app}
PID_FILE=${KAP_PID_FILE:-$APP/.kap.pid}
LOG=${KAP_LOG_FILE:-$APP/kindle-anki-port.log}
SYNC_REQUEST=${KAP_SYNC_REQUEST:-$APP/.sync-request}
OPENED_BUILD=${KAP_OPENED_BUILD_FILE:-$APP/.opened-build}

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
    [ -n "$exe" ] || return 1
    [ "$exe" = "$(canonical_path "$BIN")" ]
}

remove_pid_if_owned() {
    expected=$1
    current=$(cat "$PID_FILE" 2>/dev/null || true)
    [ "$current" = "$expected" ] && rm -f "$PID_FILE"
}

if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE" 2>/dev/null || true)
    if verified_app_pid "$old_pid"; then
        kill -USR1 "$old_pid" 2>/dev/null || true
        log "raised existing instance pid=$old_pid"
        exit 0
    fi
    rm -f "$PID_FILE"
    log "removed stale or foreign pid file"
fi

if [ ! -x "$BIN" ]; then
    log "application binary is missing or not executable: $BIN"
    exit 70
fi

if [ -f "$APP/MANIFEST.sha256" ]; then
    (cd "$APP" && sha256sum -c MANIFEST.sha256) >>"$LOG" 2>&1 || {
        log "manifest verification failed"
        exit 71
    }
fi

build_id=$(sed -n 's/.*"build_commit"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$APP/BUILD.json" 2>/dev/null | head -1)
[ -n "$build_id" ] || build_id=unknown
safe_build_id=$(printf '%s' "$build_id" | tr -c 'A-Za-z0-9._-' '_')
last_build=$(cat "$OPENED_BUILD" 2>/dev/null || true)
if [ "$last_build" != "$build_id" ] && [ -f "$DATA/collection.anki2" ]; then
    stamp=$(date '+%Y%m%d-%H%M%S')
    cp -p "$DATA/collection.anki2" "$DATA/backups/collection-before-$safe_build_id-$stamp.anki2"
    find "$DATA/backups" -type f -name 'collection-before-*.anki2' -print \
        | sort -r | awk 'NR>5' | while IFS= read -r old; do rm -f "$old"; done
    printf '%s\n' "$build_id" >"$OPENED_BUILD"
    log "created pre-open collection backup for build=$build_id"
fi

chmod 755 "$BIN" "$APP/kap-audio" "$APP/scripts/sync.sh" 2>/dev/null || true

child=
forward_signal() {
    signal_name=$1
    if [ -n "${child:-}" ] && kill -0 "$child" 2>/dev/null; then
        kill -"$signal_name" "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
        remove_pid_if_owned "$child"
    fi
    exit 128
}
trap 'forward_signal TERM' TERM
trap 'forward_signal INT' INT
trap 'forward_signal HUP' HUP

while :; do
    rm -f "$SYNC_REQUEST"
    "$BIN" --backend "$APP/libanki-kindle.so" >>"$LOG" 2>&1 &
    child=$!
    printf '%s\n' "$child" >"$PID_FILE"
    log "started pid=$child build=$build_id"
    status=0
    wait "$child" || status=$?
    remove_pid_if_owned "$child"
    child=
    log "exited status=$status"
    if [ -f "$SYNC_REQUEST" ]; then
        rm -f "$SYNC_REQUEST"
        "$APP/scripts/sync.sh" --interactive >>"$LOG" 2>&1 || log "sync failed status=$?"
        continue
    fi
    exit "$status"
done
