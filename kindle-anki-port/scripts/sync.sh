#!/bin/sh
set -eu

APP=${KAP_APP_DIR:-/mnt/us/extensions/kindle-anki-port}
DATA=${KAP_DATA_DIR:-/mnt/us/anki_data}
LOG=${KAP_LOG_FILE:-$APP/kindle-anki-port.log}
CONFIG=${KAP_CONFIG_FILE:-$APP/config.ini}
PID_FILE=${KAP_PID_FILE:-$APP/.kap.pid}
APP_BIN=${KAP_APP_BIN:-$APP/kap-app}
SYNC_BIN=${KAP_SYNC_BIN:-$APP/kap-sync}
OP_LOCK=${KAP_OPERATION_LOCK_DIR:-$APP/.kap-operation.lock}
LOCK_INIT_GRACE_ATTEMPTS=${KAP_LOCK_INIT_GRACE_ATTEMPTS:-100}

case "$LOCK_INIT_GRACE_ATTEMPTS" in
    ''|*[!0-9]*) LOCK_INIT_GRACE_ATTEMPTS=100 ;;
    0) LOCK_INIT_GRACE_ATTEMPTS=1 ;;
esac

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

op_lock_owned=0
lock_owner_pid=
release_operation_lock() {
    if [ "$op_lock_owned" = 1 ]; then
        current_owner=$(cat "$OP_LOCK/pid" 2>/dev/null || true)
        if [ -n "$lock_owner_pid" ] && [ "$current_owner" = "$lock_owner_pid" ]; then
            rm -rf "$OP_LOCK" 2>/dev/null || true
        fi
        op_lock_owned=0
        lock_owner_pid=
    fi
}

write_lock_owner() {
    new_owner=$1
    current_owner=$(cat "$OP_LOCK/pid" 2>/dev/null || true)
    [ "$current_owner" = "$lock_owner_pid" ] || return 1
    tmp="$OP_LOCK/pid.next.$$"
    printf '%s\n' "$new_owner" >"$tmp"
    if ! mv -f "$tmp" "$OP_LOCK/pid"; then
        rm -f "$tmp" 2>/dev/null || true
        return 1
    fi
    lock_owner_pid=$new_owner
}

publish_sync_lock() {
    printf '%s\n' "$$" >"$OP_LOCK/pid"
    printf '%s\n' sync >"$OP_LOCK/mode"
    op_lock_owned=1
    lock_owner_pid=$$
}

acquire_sync_lock() {
    unknown_attempts=0
    while ! mkdir "$OP_LOCK" 2>/dev/null; do
        owner=$(cat "$OP_LOCK/pid" 2>/dev/null || true)
        mode=$(cat "$OP_LOCK/mode" 2>/dev/null || true)
        case "$owner" in
            ''|*[!0-9]*)
                unknown_attempts=$((unknown_attempts + 1))
                if [ "$unknown_attempts" -lt "$LOCK_INIT_GRACE_ATTEMPTS" ]; then
                    sleep 0.02
                    continue
                fi
                latest_owner=$(cat "$OP_LOCK/pid" 2>/dev/null || true)
                case "$latest_owner" in
                    ''|*[!0-9]*)
                        rm -rf "$OP_LOCK" 2>/dev/null || true
                        unknown_attempts=0
                        continue
                        ;;
                    *)
                        unknown_attempts=0
                        continue
                        ;;
                esac
                ;;
            *)
                unknown_attempts=0
                if kill -0 "$owner" 2>/dev/null; then
                    log "sync refused while operation lock is busy mode=${mode:-unknown} owner=$owner"
                    return 74
                fi
                latest_owner=$(cat "$OP_LOCK/pid" 2>/dev/null || true)
                if [ "$latest_owner" = "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
                    rm -rf "$OP_LOCK" 2>/dev/null || true
                    continue
                fi
                ;;
        esac
        sleep 0.02
    done
    publish_sync_lock
}

acquire_sync_lock
trap 'release_operation_lock' 0

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

child=
forward_signal() {
    signal_name=$1
    signal_number=$2
    if [ -n "${child:-}" ] && kill -0 "$child" 2>/dev/null; then
        kill -"$signal_name" "$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    child=
    exit $((128 + signal_number))
}
trap 'forward_signal TERM 15' TERM
trap 'forward_signal INT 2' INT
trap 'forward_signal HUP 1' HUP

# Do not let the real sync worker touch the collection until the operation-lock
# owner record has been transferred to its eventual PID. If this wrapper is
# SIGKILLed in the fork/publication window, the gated child observes the dead
# parent and exits without ever execing kap-sync.
wrapper_pid=$$
start_gate="$OP_LOCK/start.$wrapper_pid"
(
    while :; do
        kill -0 "$wrapper_pid" 2>/dev/null || exit 75
        if [ -f "$start_gate" ]; then
            kill -0 "$wrapper_pid" 2>/dev/null || exit 75
            break
        fi
        sleep 0.02
    done
    export KAP_SYNC_HKEY="$hkey" KAP_SYNC_ENDPOINT="$endpoint"
    exec "$SYNC_BIN" --backend "$APP/libanki-kindle.so" \
        --collection "$DATA/collection.anki2" \
        --media "$DATA/collection.media" --media-db "$DATA/media.db2" "$@"
) &
child=$!
if ! write_lock_owner "$child"; then
    log "sync operation lock ownership changed before worker publication"
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    exit 75
fi
if ! : >"$start_gate"; then
    log "unable to release sync worker start gate"
    kill -TERM "$child" 2>/dev/null || true
    wait "$child" 2>/dev/null || true
    exit 75
fi
status=0
wait "$child" || status=$?
child=
unset hkey endpoint
exit "$status"
