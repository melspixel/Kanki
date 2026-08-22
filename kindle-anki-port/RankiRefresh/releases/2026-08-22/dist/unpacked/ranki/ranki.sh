#!/bin/bash

RANKI_DIR=/mnt/us/extensions/ranki
ARCH=$([ -f /lib/ld-linux-armhf.so.3 ] && echo "armhf" || echo "armel")
BIN="$RANKI_DIR/ranki-$ARCH"
SHIM="$RANKI_DIR/libkanki-webkit-$ARCH.so"
AUDIO_SERVER="$RANKI_DIR/kanki-audio-$ARCH"
# Everything the app writes goes here, and normally nowhere: a reviewer that
# is working has nothing to say, and GTK/WebKit chatter would otherwise
# accumulate on the device forever. Create a file named "enable-log" beside
# this script to collect it again when something needs looking at.
LOG=/dev/null
[ -e "$RANKI_DIR/enable-log" ] && LOG="$RANKI_DIR/ranki.log"
LOCK_DIR="$RANKI_DIR/.kanki.lock"
BACKEND_SHIM="$RANKI_DIR/libkanki-backend-redirect-$ARCH.so"
ANKI26_BACKEND="$RANKI_DIR/libanki-26.08-$ARCH.so"
DISABLE_ANKI26="$RANKI_DIR/disable-anki26"
ENABLE_RENDER_DEBUG="$RANKI_DIR/enable-render-debug"
ENABLE_LOG="$RANKI_DIR/enable-log"
RENDER_DEBUG_DIR="$RANKI_DIR/render-debug"
RENDER_DEBUG_PREVIOUS="$RANKI_DIR/render-debug.previous"
SYSTEM_FINGERPRINT_SCRIPT="$RANKI_DIR/kindle-system-fingerprint.sh"
SYSTEM_FINGERPRINT="$RANKI_DIR/system-fingerprint.txt"
CONFIG_FILE="$RANKI_DIR/config.ini"
DEFAULT_CONFIG="$RANKI_DIR/config.ini.default"
BUILD_INFO="$RANKI_DIR/KANKI_BUILD.txt"

# Leaving the app does not always end its processes: the reviewer can be torn
# down while the audio helper survives. That survivor is not harmless. It holds
# the fixed loopback port, so the next run's helper never binds and playback
# silently stops working, and the launcher used to see the old PID and refuse
# to start at all, which is what made re-entering after leaving full screen
# look like a crash. Take over from whatever is left instead of standing down.
# Scan /proc with shell builtins only. Reading each cmdline through `tr` meant
# forking once per process on the system, several hundred times over, which on
# this CPU cost seconds of startup on its own. /proc/PID/comm holds the process
# name on a single line, so the shell can read it directly; it is truncated to
# fifteen characters, which still separates these three binaries from anything
# else running.
KANKI_HELPERS=""
KANKI_REVIEWERS=""

kanki_scan_processes() {
    KANKI_HELPERS=""
    KANKI_REVIEWERS=""
    for entry in /proc/[0-9]*; do
        pid=${entry#/proc/}
        [ "$pid" = "$$" ] && continue
        comm=""
        read -r comm < "$entry/comm" 2>/dev/null || continue
        case "$comm" in
            kanki-audio-*|kanki-gst-play*) KANKI_HELPERS="$KANKI_HELPERS $pid" ;;
            ranki-arm*)                    KANKI_REVIEWERS="$KANKI_REVIEWERS $pid" ;;
        esac
    done
}

kanki_stop_previous() {
    kanki_scan_processes

    # The helpers hold a loopback socket and the audio device and own no
    # persistent state, so they can go immediately. Waiting on them politely is
    # pointless, and the port cannot be rebound until they are actually gone.
    for pid in $KANKI_HELPERS; do
        echo "$(date '+%Y-%m-%d %H:%M:%S') kanki: killing stale helper $pid" >>"$LOG"
        kill -9 "$pid" 2>/dev/null
    done

    # The reviewer owns the open collection, so it gets a chance to close the
    # database before being forced. Losing that costs user data; losing the
    # helpers costs nothing.
    if [ -n "$KANKI_REVIEWERS" ]; then
        for pid in $KANKI_REVIEWERS; do
            echo "$(date '+%Y-%m-%d %H:%M:%S') kanki: stopping stale reviewer $pid" >>"$LOG"
            kill "$pid" 2>/dev/null
        done
        if sleep 0.2 2>/dev/null; then NAP=0.2; LIMIT=15; FORCE=5; else NAP=1; LIMIT=3; FORCE=1; fi
        i=0
        while [ "$i" -lt "$LIMIT" ]; do
            sleep "$NAP"
            i=$((i + 1))
            kanki_scan_processes
            [ -z "$KANKI_REVIEWERS" ] && break
            if [ "$i" -ge "$FORCE" ]; then
                for pid in $KANKI_REVIEWERS; do kill -9 "$pid" 2>/dev/null; done
            fi
        done
        echo "$(date '+%Y-%m-%d %H:%M:%S') kanki: reviewer cleanup done remaining=[$KANKI_REVIEWERS]" >>"$LOG"
    fi

    rm -f "$RANKI_DIR/kanki-audio.pid" 2>/dev/null
    rm -rf "$LOCK_DIR" 2>/dev/null
}

kanki_stop_previous
mkdir "$LOCK_DIR" 2>/dev/null
echo $$ > "$LOCK_DIR/launcher.pid"

# The drop-in package deliberately does not overwrite config.ini. When this is
# a fresh installation, create it from the packaged default; when it is an
# in-place replacement, the existing AnkiWeb key and collection path survive.
if [ ! -r "$CONFIG_FILE" ] && [ -r "$DEFAULT_CONFIG" ]; then
    cp "$DEFAULT_CONFIG" "$CONFIG_FILE" 2>/dev/null || true
fi

COLLECTION_DIR=$(sed -n 's/^[[:space:]]*collection_dir[[:space:]]*=[[:space:]]*//p' "$CONFIG_FILE" | tail -n 1)
[ -z "$COLLECTION_DIR" ] && COLLECTION_DIR=/mnt/us/anki_data
case "$COLLECTION_DIR" in
    /*) ;;
    *) COLLECTION_DIR="$RANKI_DIR/$COLLECTION_DIR" ;;
esac
# Page zoom, as a percentage applied on top of the panel's own pixel density.
# The viewport lands near 420 CSS px at 157, which is the logical width the
# renderer's media-query rewriting already assumes, and roughly matches the
# physical text size the same CSS would have on a desktop screen. Raise it for
# Full-content zoom, magnifying text, images, padding and margins alike. It is
# the panel's own density and is best left alone: raising it makes everything
# bigger and fits less on screen.
export KANKI_ZOOM_PERCENT=100

# One rule for every deck: lift what is too small to read, hold back what
# would take the page, and move everything on the card by the same factor so
# the author's own proportions survive.
#
# The anchors are weighted by how much text each size carries, so a footnote
# marker cannot set the factor for the whole card. When lifting the smallest
# would push the largest past the ceiling, the factor lands between the two
# demands rather than serving one and ignoring the other.
#
# Set either to 0 to drop that end of the rule.
export KANKI_FLOOR_PX=24
export KANKI_CEILING_PX=56

# Han text keeps an absolute floor of its own. The rule above already brings
# the smallest Latin text up to the floor, but Han carries more detail per em,
# and a deck writing its gloss smaller than its headword leaves it short even
# then.
export KANKI_MIN_CJK_PX=22

# Cap on relative line height. Templates written for a monitor commonly ask for
# 1.5 to 1.8, which on this page costs whole lines to whitespace. Only ever
# reduces, and ignores line heights given in pixels, where a fixed-height box
# may depend on them. 0 leaves leading as the deck wrote it.
export KANKI_LINE_PERCENT=130

# Cap on a block's own vertical margins and padding, for section gaps written
# when the screen was roomier. Horizontal spacing is untouched: it sets the
# text column, not its length.
export KANKI_BLOCK_MAX_PX=12

# How far the page control sits above the bottom edge of the card view.
export KANKI_PAGER_BOTTOM_PX=2

# How much of the previous screen a page turn keeps in view.
export KANKI_PAGE_OVERLAP_PX=80
# Height cap for the reviewer's rating row, in device pixels. Ranki assigns
# that row 90 x scaling in code, which lands near 190 on this panel; the card
# view is the only part of the window set to expand, so what the row gives up
# becomes reading space. 72 is roughly 6mm and stays comfortable to press.
# Only rows already taller than 120 are affected, which leaves the deck list's
# own 100px rows alone. Set 0 to leave the row exactly as Ranki sizes it.
export KANKI_BUTTON_HEIGHT_PX=72

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
# Off by default. Capturing forty pairs of HTML per launch and a computed
# layout record per element is what a diagnosis needs and pure cost once the
# diagnosis is done - it grew the log from one megabyte to nine in a day of
# testing. Create a file named "enable-render-debug" beside this script to
# turn it back on without reinstalling.
unset KANKI_RENDER_DEBUG
RENDER_DEBUG="disabled"
if [ ! -e "$ENABLE_RENDER_DEBUG" ]; then
    # Nothing rotates these once capture is off, so a directory left from the
    # last diagnostic run would sit on the device forever, and the log with it.
    # Both are ours and both are dead weight while nothing is being collected.
    rm -rf "$RENDER_DEBUG_DIR" "$RENDER_DEBUG_PREVIOUS" 2>/dev/null || true
    [ -e "$ENABLE_LOG" ] || rm -f "$RANKI_DIR/ranki.log" 2>/dev/null || true
fi
if [ -e "$ENABLE_RENDER_DEBUG" ]; then
    export KANKI_RENDER_DEBUG=1
    RENDER_DEBUG="enabled"
    rm -rf "$RENDER_DEBUG_PREVIOUS" 2>/dev/null || true
    [ -d "$RENDER_DEBUG_DIR" ] && mv "$RENDER_DEBUG_DIR" "$RENDER_DEBUG_PREVIOUS" 2>/dev/null || true
    mkdir -p "$RENDER_DEBUG_DIR" 2>/dev/null || true
fi

# Fingerprint the actual Kindle userspace used for this run. The fingerprint
# contains only system/runtime information, and is copied next to the HTML
# captures so it can be matched against an extracted Amazon firmware rootfs.
# Capturing this walks the font directories and checksums the render stack,
# including an 18MB WebKit. That is seconds of startup on this CPU, spent
# re-deriving something that only changes when the firmware does. Keep the
# previous capture unless the reported system version has moved.
SYSTEM_FINGERPRINT_STATUS="missing"
FIRMWARE_STAMP=$(cat /etc/version.txt 2>/dev/null | head -n 2 | tr -d '\n')
FIRMWARE_STAMP_FILE="$RANKI_DIR/.system-fingerprint.stamp"
if [ -r "$SYSTEM_FINGERPRINT_SCRIPT" ]; then
    if [ -r "$SYSTEM_FINGERPRINT" ] && [ -r "$FIRMWARE_STAMP_FILE" ] \
            && [ "$(cat "$FIRMWARE_STAMP_FILE" 2>/dev/null)" = "$FIRMWARE_STAMP" ]; then
        SYSTEM_FINGERPRINT_STATUS="cached"
    else
        sh "$SYSTEM_FINGERPRINT_SCRIPT" "$SYSTEM_FINGERPRINT" >/dev/null 2>&1 || true
        printf '%s' "$FIRMWARE_STAMP" > "$FIRMWARE_STAMP_FILE" 2>/dev/null || true
    fi
    if [ -r "$SYSTEM_FINGERPRINT" ]; then
        [ "$SYSTEM_FINGERPRINT_STATUS" = "missing" ] && SYSTEM_FINGERPRINT_STATUS="captured"
        [ "$RENDER_DEBUG" = "enabled" ] && cp "$SYSTEM_FINGERPRINT" "$RENDER_DEBUG_DIR/00-system-fingerprint.txt" 2>/dev/null || true
    fi
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
    [ -r "$BUILD_INFO" ] && sed 's/^/build: /' "$BUILD_INFO"
    echo "launcher=direct-library-shortcut"
    echo "media=$KANKI_MEDIA_DIR"
    echo "backend_request=$BACKEND_REQUEST"
    echo "render_debug=$RENDER_DEBUG"
    echo "system_fingerprint=$SYSTEM_FINGERPRINT_STATUS"
    [ "$SYSTEM_FINGERPRINT_STATUS" = "captured" ] && echo "system_fingerprint_file=$SYSTEM_FINGERPRINT"
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
    # Probing loads GStreamer and enumerates every plugin. Like the system
    # fingerprint this only changes with the firmware, so reuse the last
    # answer rather than paying for it on every launch.
    GST_PROBE_CACHE="$RANKI_DIR/.gst-probe.cache"
    if [ -r "$GST_PROBE_CACHE" ] && [ -r "$FIRMWARE_STAMP_FILE" ] \
            && [ "$(cat "$FIRMWARE_STAMP_FILE" 2>/dev/null)" = "$FIRMWARE_STAMP" ]; then
        sed 's/^/gst-probe: /' "$GST_PROBE_CACHE"
        echo "gst-probe-source=cache"
    else
        if [ -r "$KANKI_GST_PLAYER" ] && [ -x "$KANKI_GST_LOADER" ]; then
            "$KANKI_GST_LOADER" "$KANKI_GST_PLAYER" --probe >"$GST_PROBE_CACHE" 2>&1
        elif [ -x "$KANKI_GST_PLAYER" ]; then
            "$KANKI_GST_PLAYER" --probe >"$GST_PROBE_CACHE" 2>&1
        else
            echo "gst-probe: native player missing/unreadable" >"$GST_PROBE_CACHE"
        fi
        sed 's/^/gst-probe: /' "$GST_PROBE_CACHE"
        echo "gst-probe-source=fresh"
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
