#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
LOCK="$DIR/.kanki.lock"
AUDIO_PID_FILE="$DIR/.audio.pid"
AUDIO_PID=
START_SYNC_PAGE=0
LAST_SYNC_STATUS=0

mkdir -p "$DIR"
if ! mkdir "$LOCK" 2>/dev/null; then
    PID=$(cat "$LOCK/pid" 2>/dev/null || true)
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        if [ -x "$DIR/kanki-raise" ] && "$DIR/kanki-raise" >>"$LOG" 2>&1; then
            printf '%s existing Kanki window reactivated pid=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PID" >>"$LOG"
        else
            printf '%s duplicate launch found live pid=%s but window reactivation failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$PID" >>"$LOG"
        fi
        exit 0
    fi
    rm -rf "$LOCK"
    mkdir "$LOCK"
fi
printf '%s\n' "$$" >"$LOCK/pid"

stop_audio() {
    if [ -n "${AUDIO_PID:-}" ]; then
        kill "$AUDIO_PID" 2>/dev/null || true
        wait "$AUDIO_PID" 2>/dev/null || true
        AUDIO_PID=
    fi
    rm -f "$AUDIO_PID_FILE"
}

cleanup() {
    stop_audio
    rm -rf "$LOCK"
}
trap cleanup EXIT INT TERM

if [ -f "$DIR/MANIFEST.sha256" ]; then
    (cd "$DIR" && sha256sum -c MANIFEST.sha256) >>"$LOG" 2>&1 || {
        printf '%s manifest verification failed\n' "$(date '+%Y-%m-%d %H:%M:%S')" >>"$LOG"
        exit 71
    }
fi

export KANKI_MEDIA_DIR=/mnt/us/anki_data/collection.media
export KANKI_GST_PLAYER="$DIR/kanki-gst-play"
export KANKI_GST_LOADER=/lib/ld-linux-armhf.so.3
export GST_PLUGIN_PATH=/usr/lib/gstreamer-0.10:/usr/lib/gstreamer-1.0
chmod 755 "$DIR/kanki-device" "$DIR/kanki-audio" "$DIR/kanki-gst-play" "$DIR/kanki-raise" "$DIR/kanki-sync.sh" 2>/dev/null || true

start_audio() {
    if [ -f "$AUDIO_PID_FILE" ]; then
        OLD_AUDIO_PID=$(cat "$AUDIO_PID_FILE" 2>/dev/null || true)
        [ -n "$OLD_AUDIO_PID" ] && kill "$OLD_AUDIO_PID" 2>/dev/null || true
    fi
    "$DIR/kanki-audio" >>"$LOG" 2>&1 &
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
        if KANKI_SYNC_FROM_LAUNCHER=1 "$DIR/kanki-sync.sh" "$SYNC_ARGS"; then
            STATUS=0
        else
            STATUS=$?
        fi
    else
        if KANKI_SYNC_FROM_LAUNCHER=1 "$DIR/kanki-sync.sh"; then
            STATUS=0
        else
            STATUS=$?
        fi
    fi
    printf '%s launcher sync end mode=%s status=%s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$MODE" "$STATUS" >>"$LOG"
    return "$STATUS"
}

while :; do
    start_audio
    if [ "$START_SYNC_PAGE" -eq 1 ]; then
        if "$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" --start-sync --sync-status "$LAST_SYNC_STATUS" >>"$LOG" 2>&1; then
            STATUS=0
        else
            STATUS=$?
        fi
    else
        if "$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" >>"$LOG" 2>&1; then
            STATUS=0
        else
            STATUS=$?
        fi
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
