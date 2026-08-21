#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
KANKI_OPERATION_ROOT=$DIR
KANKI_OPERATION_LOCK_FILE="$DIR/.kanki.operation.lock"
KANKI_OPERATION_STATE_DIR="$DIR/.kanki.lock"
KANKI_FLOCK=/usr/bin/flock
AUDIO_PID_FILE="$DIR/.audio.pid"
DIAG_PID_FILE="$DIR/.diag.pid"
DEBUG_DIR="$DIR/render-debug"
DEBUG_PREVIOUS="$DIR/render-debug.previous"
AUDIO_PID=
DIAG_PID=
FOREGROUND_PID=
START_SYNC_PAGE=0
LAST_SYNC_STATUS=0

verify_installation() {
    if [ ! -f "$DIR/MANIFEST.sha256" ] || \
        [ -L "$DIR/MANIFEST.sha256" ]; then
        printf '%s package manifest missing or symbolic: MANIFEST.sha256\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >&2
        return 71
    fi
    if [ ! -f "$DIR/kanki-verify.sh" ] || \
        [ -L "$DIR/kanki-verify.sh" ]; then
        printf '%s install verifier missing or symbolic\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >&2
        return 73
    fi
    VERIFY_RECORD=$(grep -E '^[0-9a-fA-F]{64}  \./kanki-verify\.sh$' \
        "$DIR/MANIFEST.sha256" 2>/dev/null || true)
    if [ -z "$VERIFY_RECORD" ] || \
        ! printf '%s\n' "$VERIFY_RECORD" | (cd "$DIR" && sha256sum -c -) \
            >/dev/null 2>&1; then
        printf '%s install verifier does not match manifest\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" >&2
        return 73
    fi
    if sh "$DIR/kanki-verify.sh" "$DIR" >/dev/null; then
        :
    else
        STATUS=$?
        printf '%s installation integrity verification failed status=%s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "$STATUS" >&2
        return "$STATUS"
    fi
    for REQUIRED in \
        './BUILD.json' \
        './libanki-kanki.so' \
        './kanki-device' \
        './kanki-sync' \
        './kanki-diag' \
        './kanki-audio' \
        './kanki-gst-play' \
        './kanki-operation-lock.sh' \
        './.kanki.operation.lock' \
        './kanki-verify.sh' \
        './assets/device/reviewer-shell.html' \
        './assets/reviewer/reviewer.js' \
        './assets/reviewer/diagnostics.js'; do
        if ! grep -F "  $REQUIRED" "$DIR/MANIFEST.sha256" >/dev/null 2>&1; then
            printf '%s package manifest missing required component=%s\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "$REQUIRED" >&2
            return 72
        fi
    done
}

verify_installation
umask 077

if [ ! -f "$DIR/kanki-operation-lock.sh" ] ||
    [ -L "$DIR/kanki-operation-lock.sh" ]; then
    printf '%s collection operation lock helper missing or symbolic\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" >&2
    exit 73
fi
. "$DIR/kanki-operation-lock.sh"
if kanki_operation_lock_acquire launch; then
    :
else
    STATUS=$?
    BUSY_MODE=$(cat "$KANKI_OPERATION_STATE_DIR/mode" 2>/dev/null || true)
    BUSY_PID=$(cat "$KANKI_OPERATION_STATE_DIR/pid" 2>/dev/null || true)
    if [ "$STATUS" -eq 74 ] && [ "$BUSY_MODE" = launch ]; then
        if [ -x "$DIR/kanki-raise" ] &&
            DISPLAY="${DISPLAY:-:0}" "$DIR/kanki-raise" >>"$LOG" 2>&1; then
            printf '%s existing Kanki window reactivated owner=%s\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "${BUSY_PID:-unknown}" >>"$LOG"
        else
            printf '%s duplicate launch found active reviewer owner=%s but window reactivation failed\n' \
                "$(date '+%Y-%m-%d %H:%M:%S')" "${BUSY_PID:-unknown}" >>"$LOG"
        fi
        exit 0
    fi
    printf '%s launch refused: collection operation busy mode=%s owner=%s status=%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S')" "${BUSY_MODE:-unknown}" \
        "${BUSY_PID:-unknown}" "$STATUS" >>"$LOG"
    exit "$STATUS"
fi
trap 'kanki_operation_lock_cleanup' EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s installation integrity verification passed\n' \
    "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
printf '%s build identity: ' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
tr '\n' ' ' <"$DIR/BUILD.json" >>"$LOG"
printf '\n' >>"$LOG"

stop_audio() {
    if [ -n "${AUDIO_PID:-}" ]; then
        kill "$AUDIO_PID" 2>/dev/null || true
        wait "$AUDIO_PID" 2>/dev/null || true
        AUDIO_PID=
    fi
    rm -f "$AUDIO_PID_FILE"
}

stop_diag() {
    if [ -n "${DIAG_PID:-}" ]; then
        kill "$DIAG_PID" 2>/dev/null || true
        wait "$DIAG_PID" 2>/dev/null || true
        DIAG_PID=
    fi
    rm -f "$DIAG_PID_FILE"
}

cleanup() {
    stop_audio
    stop_diag
    kanki_operation_lock_cleanup
}

forward_signal() {
    SIGNAL_NAME=$1
    SIGNAL_NUMBER=$2
    trap - HUP INT TERM
    if [ -n "${FOREGROUND_PID:-}" ] &&
        kill -0 "$FOREGROUND_PID" 2>/dev/null; then
        kill -"$SIGNAL_NAME" "$FOREGROUND_PID" 2>/dev/null || true
        wait "$FOREGROUND_PID" 2>/dev/null || true
    fi
    FOREGROUND_PID=
    exit $((128 + SIGNAL_NUMBER))
}

trap cleanup EXIT
trap 'forward_signal HUP 1' HUP
trap 'forward_signal INT 2' INT
trap 'forward_signal TERM 15' TERM

export KANKI_MEDIA_DIR=/mnt/us/anki_data/collection.media
export KANKI_GST_PLAYER="$DIR/kanki-gst-play"
export KANKI_GST_LOADER=/lib/ld-linux-armhf.so.3
export GST_PLUGIN_PATH=/usr/lib/gstreamer-0.10:/usr/lib/gstreamer-1.0
chmod 755 "$DIR/kanki-device" "$DIR/kanki-audio" "$DIR/kanki-diag" "$DIR/kanki-gst-play" "$DIR/kanki-raise" "$DIR/kanki-sync.sh" "$DIR/kanki-report.sh" "$DIR/kanki-verify.sh" 2>/dev/null || true

prepare_diagnostic_dirs() {
    rm -rf "$DEBUG_PREVIOUS"
    if [ -d "$DEBUG_DIR" ]; then
        mv "$DEBUG_DIR" "$DEBUG_PREVIOUS" || {
            printf '%s diagnostic rotation failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
            return 74
        }
    fi
    mkdir -p "$DEBUG_DIR" || {
        printf '%s diagnostic directory creation failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
        return 75
    }
}

write_diagnostic_config() {
    CONFIG_TMP="$DEBUG_DIR/config.js.tmp.$$"
    if [ -f "$DIR/enable-render-capture" ]; then
        printf '%s\n' 'window.kankiDiagnostics={rawCapture:true,protocolVersion:1};' >"$CONFIG_TMP"
    else
        printf '%s\n' 'window.kankiDiagnostics={rawCapture:false,protocolVersion:1};' >"$CONFIG_TMP"
    fi
    mv "$CONFIG_TMP" "$DEBUG_DIR/config.js"
}

start_diag() {
    prepare_diagnostic_dirs
    write_diagnostic_config
    if [ -f "$DIAG_PID_FILE" ]; then
        OLD_DIAG_PID=$(cat "$DIAG_PID_FILE" 2>/dev/null || true)
        [ -n "$OLD_DIAG_PID" ] && kill "$OLD_DIAG_PID" 2>/dev/null || true
    fi
    "$DIR/kanki-diag" 9>&- >>"$LOG" 2>&1 &
    DIAG_PID=$!
    printf '%s\n' "$DIAG_PID" >"$DIAG_PID_FILE"
    sleep 1
    if ! kill -0 "$DIAG_PID" 2>/dev/null; then
        wait "$DIAG_PID" 2>/dev/null || true
        DIAG_PID=
        rm -f "$DIAG_PID_FILE"
        printf '%s diagnostic service failed to start\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
        return 76
    fi
    printf '%s diagnostic service started raw_capture=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$([ -f "$DIR/enable-render-capture" ] && echo enabled || echo disabled)" >>"$LOG"
}

start_audio() {
    if [ -f "$AUDIO_PID_FILE" ]; then
        OLD_AUDIO_PID=$(cat "$AUDIO_PID_FILE" 2>/dev/null || true)
        [ -n "$OLD_AUDIO_PID" ] && kill "$OLD_AUDIO_PID" 2>/dev/null || true
    fi
    "$DIR/kanki-audio" 9>&- >>"$LOG" 2>&1 &
    AUDIO_PID=$!
    printf '%s\n' "$AUDIO_PID" >"$AUDIO_PID_FILE"
}

run_sync() {
    MODE=$1
    case "$MODE" in
        normal) SYNC_ARGS= ;;
        upload) SYNC_ARGS=--full-upload ;;
        download) SYNC_ARGS=--full-download ;;
        *) return 64 ;;
    esac
    printf '%s launcher sync begin mode=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" >>"$LOG"
    if [ -n "$SYNC_ARGS" ]; then
        KANKI_OPERATION_LOCK_OWNER=$$ \
            "$DIR/kanki-sync.sh" "$SYNC_ARGS" &
    else
        KANKI_OPERATION_LOCK_OWNER=$$ "$DIR/kanki-sync.sh" &
    fi
    FOREGROUND_PID=$!
    if wait "$FOREGROUND_PID"; then
        STATUS=0
    else
        STATUS=$?
    fi
    FOREGROUND_PID=
    printf '%s launcher sync end mode=%s status=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$STATUS" >>"$LOG"
    return "$STATUS"
}

run_device() {
    if [ "$START_SYNC_PAGE" -eq 1 ]; then
        "$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" \
            --start-sync --sync-status "$LAST_SYNC_STATUS" >>"$LOG" 2>&1 &
    else
        "$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" \
            >>"$LOG" 2>&1 &
    fi
    FOREGROUND_PID=$!
    if wait "$FOREGROUND_PID"; then
        STATUS=0
    else
        STATUS=$?
    fi
    FOREGROUND_PID=
    return "$STATUS"
}

start_diag
while :; do
    start_audio
    if run_device; then
        STATUS=0
    else
        STATUS=$?
    fi
    stop_audio

    case "$STATUS" in
        80) MODE=normal ;;
        81) MODE=upload ;;
        82) MODE=download ;;
        *) exit "$STATUS" ;;
    esac

    if run_sync "$MODE"; then
        LAST_SYNC_STATUS=0
        START_SYNC_PAGE=0
    else
        LAST_SYNC_STATUS=$?
        START_SYNC_PAGE=1
    fi
done
