#!/bin/bash

RANKI_DIR=/mnt/us/extensions/ranki
ARCH=$([ -f /lib/ld-linux-armhf.so.3 ] && echo "armhf" || echo "armel")
BIN="$RANKI_DIR/ranki-$ARCH"
SHIM="$RANKI_DIR/libkanki-webkit-$ARCH.so"
AUDIO_SERVER="$RANKI_DIR/kanki-audio-$ARCH"
LOG="$RANKI_DIR/ranki.log"

# Resolve the collection media directory from Ranki's config. Relative paths are
# interpreted relative to the extension directory, matching Ranki's behavior.
COLLECTION_DIR=$(sed -n 's/^[[:space:]]*collection_dir[[:space:]]*=[[:space:]]*//p' "$RANKI_DIR/config.ini" | tail -n 1)
[ -z "$COLLECTION_DIR" ] && COLLECTION_DIR=/mnt/us/anki_data
case "$COLLECTION_DIR" in
    /*) ;;
    *) COLLECTION_DIR="$RANKI_DIR/$COLLECTION_DIR" ;;
esac
export KANKI_MEDIA_DIR="$COLLECTION_DIR/collection.media"

# Kill a stale helper left behind by an abnormal exit, then start a fresh one.
if [ -f "$RANKI_DIR/kanki-audio.pid" ]; then
    OLD_PID=$(cat "$RANKI_DIR/kanki-audio.pid" 2>/dev/null)
    [ -n "$OLD_PID" ] && kill "$OLD_PID" 2>/dev/null || true
fi
"$AUDIO_SERVER" >>"$LOG" 2>&1 &
AUDIO_PID=$!
echo "$AUDIO_PID" > "$RANKI_DIR/kanki-audio.pid"

cleanup() {
    kill "$AUDIO_PID" 2>/dev/null || true
    rm -f "$RANKI_DIR/kanki-audio.pid"
}
trap cleanup EXIT INT TERM

# Kindle's GTK/WebKit emits a large amount of non-fatal diagnostics. Redirecting
# them prevents the launcher layer from painting those messages over the e-ink UI.
export LD_PRELOAD="$SHIM${LD_PRELOAD:+:$LD_PRELOAD}"
"$BIN" "$@" >>"$LOG" 2>&1
STATUS=$?
exit "$STATUS"
