#!/bin/bash

RANKI_DIR=/mnt/us/extensions/ranki
ARCH=$([ -f /lib/ld-linux-armhf.so.3 ] && echo "armhf" || echo "armel")
BIN="$RANKI_DIR/ranki-$ARCH"
SHIM="$RANKI_DIR/libkanki-webkit-$ARCH.so"
AUDIO_SERVER="$RANKI_DIR/kanki-audio-$ARCH"
LOG="$RANKI_DIR/ranki.log"
LOCK_DIR="$RANKI_DIR/.kanki.lock"

acquire_lock() {
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/launcher.pid"
        return 0
    fi
    OLD_PID=$(cat "$LOCK_DIR/launcher.pid" 2>/dev/null)
    if [ -n "$OLD_PID" ] && kill -0 "$OLD_PID" 2>/dev/null; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') kanki: duplicate launch ignored (launcher pid $OLD_PID)" >>"$LOG"
        return 1
    fi
    rm -rf "$LOCK_DIR"
    mkdir "$LOCK_DIR" 2>/dev/null || return 1
    echo $$ > "$LOCK_DIR/launcher.pid"
}
acquire_lock || exit 0

COLLECTION_DIR=$(sed -n 's/^[[:space:]]*collection_dir[[:space:]]*=[[:space:]]*//p' "$RANKI_DIR/config.ini" | tail -n 1)
[ -z "$COLLECTION_DIR" ] && COLLECTION_DIR=/mnt/us/anki_data
case "$COLLECTION_DIR" in
    /*) ;;
    *) COLLECTION_DIR="$RANKI_DIR/$COLLECTION_DIR" ;;
esac
export KANKI_MEDIA_DIR="$COLLECTION_DIR/collection.media"
export KANKI_GST_PLAYER="$RANKI_DIR/kanki-gst-play-$ARCH"

{
    echo ""
    echo "===== Kanki start $(date '+%Y-%m-%d %H:%M:%S') ====="
    echo "arch=$ARCH"
    echo "media=$KANKI_MEDIA_DIR"
    echo "native_player=$KANKI_GST_PLAYER"
    if [ -x "$KANKI_GST_PLAYER" ]; then
        "$KANKI_GST_PLAYER" --probe 2>&1 | sed 's/^/gst-probe: /'
    else
        echo "gst-probe: native player missing"
    fi
} >>"$LOG"

if [ -f "$RANKI_DIR/kanki-audio.pid" ]; then
    OLD_PID=$(cat "$RANKI_DIR/kanki-audio.pid" 2>/dev/null)
    [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null || true
fi
"$AUDIO_SERVER" >>"$LOG" 2>&1 &
AUDIO_PID=$!
echo "$AUDIO_PID" > "$RANKI_DIR/kanki-audio.pid"

RANKI_PID=""
cleanup() {
    trap - EXIT INT TERM
    [ -n "$RANKI_PID" ] && kill "$RANKI_PID" 2>/dev/null || true
    kill "$AUDIO_PID" 2>/dev/null || true
    rm -f "$RANKI_DIR/kanki-audio.pid"
    rm -rf "$LOCK_DIR"
}
trap cleanup EXIT INT TERM

export LD_PRELOAD="$SHIM${LD_PRELOAD:+:$LD_PRELOAD}"
"$BIN" "$@" >>"$LOG" 2>&1 &
RANKI_PID=$!
echo "$RANKI_PID" > "$LOCK_DIR/ranki.pid"
wait "$RANKI_PID"
STATUS=$?
RANKI_PID=""
exit "$STATUS"
