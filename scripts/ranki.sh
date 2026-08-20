#!/bin/bash

RANKI_DIR=/mnt/us/extensions/ranki
ARCH=$([ -f /lib/ld-linux-armhf.so.3 ] && echo "armhf" || echo "armel")
BIN="$RANKI_DIR/ranki-$ARCH"
SHIM="$RANKI_DIR/libkanki-webkit-$ARCH.so"
AUDIO_SERVER="$RANKI_DIR/kanki-audio-$ARCH"
LOG="$RANKI_DIR/ranki.log"
LOCK_DIR="$RANKI_DIR/.kanki.lock"

# Prevent a second Ranki process from opening the same Anki collection.  A
# duplicate instance is what produces "Anki already open, or media currently
# syncing" while the first reviewer is still visible underneath.
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

    # Stale lock after a crash/reboot.
    rm -rf "$LOCK_DIR"
    if mkdir "$LOCK_DIR" 2>/dev/null; then
        echo $$ > "$LOCK_DIR/launcher.pid"
        return 0
    fi
    return 1
}

acquire_lock || exit 0

# Resolve the collection media directory from Ranki's config. Relative paths are
# interpreted relative to the extension directory, matching Ranki's behavior.
COLLECTION_DIR=$(sed -n 's/^[[:space:]]*collection_dir[[:space:]]*=[[:space:]]*//p' "$RANKI_DIR/config.ini" | tail -n 1)
[ -z "$COLLECTION_DIR" ] && COLLECTION_DIR=/mnt/us/anki_data
case "$COLLECTION_DIR" in
    /*) ;;
    *) COLLECTION_DIR="$RANKI_DIR/$COLLECTION_DIR" ;;
esac
export KANKI_MEDIA_DIR="$COLLECTION_DIR/collection.media"

{
    echo ""
    echo "===== Kanki start $(date '+%Y-%m-%d %H:%M:%S') ====="
    echo "arch=$ARCH"
    echo "media=$KANKI_MEDIA_DIR"
    [ -x /usr/bin/gst-launch-0.10 ] && echo "gst=/usr/bin/gst-launch-0.10" || echo "gst=/usr/bin/gst-launch"
} >>"$LOG"

# Kill a stale helper left behind by an abnormal exit, then start a fresh one.
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
    if [ -n "$RANKI_PID" ]; then
        kill "$RANKI_PID" 2>/dev/null || true
    fi
    kill "$AUDIO_PID" 2>/dev/null || true
    rm -f "$RANKI_DIR/kanki-audio.pid"
    rm -rf "$LOCK_DIR"
}
trap cleanup EXIT INT TERM

# Kindle's GTK/WebKit emits a large amount of non-fatal diagnostics. Redirecting
# them prevents the launcher layer from painting those messages over the e-ink UI.
export LD_PRELOAD="$SHIM${LD_PRELOAD:+:$LD_PRELOAD}"
"$BIN" "$@" >>"$LOG" 2>&1 &
RANKI_PID=$!
echo "$RANKI_PID" > "$LOCK_DIR/ranki.pid"
wait "$RANKI_PID"
STATUS=$?
RANKI_PID=""
exit "$STATUS"
