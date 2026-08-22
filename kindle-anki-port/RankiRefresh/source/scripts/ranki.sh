#!/bin/bash

RANKI_DIR=/mnt/us/extensions/ranki
ARCH=$([ -f /lib/ld-linux-armhf.so.3 ] && echo "armhf" || echo "armel")
BIN="$RANKI_DIR/ranki-$ARCH"
SHIM="$RANKI_DIR/libkanki-webkit-$ARCH.so"
AUDIO_SERVER="$RANKI_DIR/kanki-audio-$ARCH"
LOG="$RANKI_DIR/ranki.log"
LOCK_DIR="$RANKI_DIR/.kanki.lock"
BACKEND_SHIM="$RANKI_DIR/libkanki-backend-redirect-$ARCH.so"
ANKI26_BACKEND="$RANKI_DIR/libanki-26.08-$ARCH.so"
DISABLE_ANKI26="$RANKI_DIR/disable-anki26"
DISABLE_RENDER_DEBUG="$RANKI_DIR/disable-render-debug"
RENDER_DEBUG_DIR="$RANKI_DIR/render-debug"
RENDER_DEBUG_PREVIOUS="$RANKI_DIR/render-debug.previous"

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
if [ "$ARCH" = armhf ]; then
    export KANKI_GST_LOADER=/lib/ld-linux-armhf.so.3
else
    export KANKI_GST_LOADER=/lib/ld-linux.so.3
fi

# Anki 26.08 is currently provided only for hard-float Kindles. Keeping a
# sentinel file named "disable-anki26" beside this script forces the original
# embedded RAnki backend, which makes rollback possible without reinstalling.
BACKEND_REQUEST="embedded-25.09"
PRELOAD="$SHIM"
unset KANKI_ANKI_BACKEND
if [ "$ARCH" = armhf ] && [ ! -e "$DISABLE_ANKI26" ] \
        && [ -r "$ANKI26_BACKEND" ] && [ -r "$BACKEND_SHIM" ]; then
    export KANKI_ANKI_BACKEND="$ANKI26_BACKEND"
    PRELOAD="$BACKEND_SHIM:$PRELOAD"
    BACKEND_REQUEST="external-26.08"
fi

# Renderer diagnostics are on by default in development builds. They capture
# the exact HTML before/after Kanki preprocessing for the first 40 WebKit loads,
# while computed-style/layout snapshots are written to ranki.log. Preserve one
# previous launch so a failed relaunch does not immediately destroy evidence.
unset KANKI_RENDER_DEBUG
RENDER_DEBUG="disabled"
if [ ! -e "$DISABLE_RENDER_DEBUG" ]; then
    export KANKI_RENDER_DEBUG=1
    RENDER_DEBUG="enabled"
    rm -rf "$RENDER_DEBUG_PREVIOUS" 2>/dev/null || true
    [ -d "$RENDER_DEBUG_DIR" ] && mv "$RENDER_DEBUG_DIR" "$RENDER_DEBUG_PREVIOUS" 2>/dev/null || true
    mkdir -p "$RENDER_DEBUG_DIR" 2>/dev/null || true
fi

# MTP clients may drop Unix executable bits on files copied to /mnt/us. The
# native player can still be launched through the system ELF loader as long as
# it is readable, but chmod is harmless and helps on filesystems that preserve it.
chmod 755 "$KANKI_GST_PLAYER" 2>/dev/null || true
chmod 755 "$AUDIO_SERVER" "$BIN" 2>/dev/null || true

{
    echo ""
    echo "===== Kanki start $(date '+%Y-%m-%d %H:%M:%S') ====="
    echo "arch=$ARCH"
    echo "media=$KANKI_MEDIA_DIR"
    echo "backend_request=$BACKEND_REQUEST"
    echo "render_debug=$RENDER_DEBUG"
    if [ "$RENDER_DEBUG" = "enabled" ]; then
        echo "render_debug_dir=$RENDER_DEBUG_DIR"
        echo "render_debug_previous=$RENDER_DEBUG_PREVIOUS"
        echo "render_debug_capture_limit=40"
        echo "render_debug_note=input.html is exact RAnki HTML; patched.html is exact WebKit input; KANKI_RENDER lines are computed layout"
    fi
    if [ "$BACKEND_REQUEST" = "external-26.08" ]; then
        echo "backend_file=$ANKI26_BACKEND"
        echo "backend_disable_sentinel=$DISABLE_ANKI26"
    elif [ -e "$DISABLE_ANKI26" ]; then
        echo "backend_note=Anki26 disabled by sentinel"
    fi
    echo "native_player=$KANKI_GST_PLAYER"
    echo "native_loader=$KANKI_GST_LOADER"
    ls -l "$KANKI_GST_PLAYER" 2>&1 | sed 's/^/player-file: /'
    if [ -r "$KANKI_GST_PLAYER" ] && [ -x "$KANKI_GST_LOADER" ]; then
        "$KANKI_GST_LOADER" "$KANKI_GST_PLAYER" --probe 2>&1 | sed 's/^/gst-probe: /'
    elif [ -x "$KANKI_GST_PLAYER" ]; then
        "$KANKI_GST_PLAYER" --probe 2>&1 | sed 's/^/gst-probe: /'
    else
        echo "gst-probe: native player missing/unreadable"
    fi
    for D in /usr/bin/curl /usr/bin/wget /bin/busybox; do
        [ -x "$D" ] && echo "downloader=$D"
    done
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

export LD_PRELOAD="$PRELOAD${LD_PRELOAD:+:$LD_PRELOAD}"
"$BIN" "$@" >>"$LOG" 2>&1 &
RANKI_PID=$!
echo "$RANKI_PID" > "$LOCK_DIR/ranki.pid"
wait "$RANKI_PID"
STATUS=$?
RANKI_PID=""
exit "$STATUS"
