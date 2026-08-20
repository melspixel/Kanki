#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
LOG="$DIR/kanki.log"
LOCK="$DIR/.kanki.lock"
AUDIO_PID_FILE="$DIR/.audio.pid"

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
AUDIO_PID=
cleanup() {
    if [ -n "${AUDIO_PID:-}" ]; then kill "$AUDIO_PID" 2>/dev/null || true; fi
    rm -f "$AUDIO_PID_FILE"
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
chmod 755 "$DIR/kanki-device" "$DIR/kanki-audio" "$DIR/kanki-gst-play" 2>/dev/null || true

if [ -f "$AUDIO_PID_FILE" ]; then
    OLD_AUDIO_PID=$(cat "$AUDIO_PID_FILE" 2>/dev/null || true)
    [ -n "$OLD_AUDIO_PID" ] && kill "$OLD_AUDIO_PID" 2>/dev/null || true
fi
"$DIR/kanki-audio" >>"$LOG" 2>&1 &
AUDIO_PID=$!
printf '%s\n' "$AUDIO_PID" >"$AUDIO_PID_FILE"

"$DIR/kanki-device" --backend "$DIR/libanki-kanki.so" >>"$LOG" 2>&1
STATUS=$?
exit "$STATUS"
