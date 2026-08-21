#!/bin/sh
set -eu

DIR=/mnt/us/extensions/kanki
OUT_ROOT=/mnt/us/kanki_reports
STAMP=$(date '+%Y%m%d-%H%M%S' 2>/dev/null || echo unknown-time)
WORK="$OUT_ROOT/kanki-report-$STAMP"
ARCHIVE="$OUT_ROOT/kanki-report-$STAMP.tar.gz"
LOG="$DIR/kanki.log"
RENDER_DEBUG="$DIR/render-debug"

mkdir -p "$WORK"

copy_if_readable() {
    SOURCE=$1
    TARGET=$2
    if [ -r "$SOURCE" ]; then
        cp "$SOURCE" "$TARGET"
    fi
}

redact_log() {
    SOURCE=$1
    TARGET=$2
    if [ ! -r "$SOURCE" ]; then
        : >"$TARGET"
        return
    fi
    # Kanki deliberately does not log auth material. This filter is a second
    # defensive layer: drop any line that looks credential-, account-, network-
    # or device-identity-related rather than trying to partially mask it.
    if command -v grep >/dev/null 2>&1; then
        grep -vi \
            -e 'hkey' \
            -e 'password' \
            -e 'token' \
            -e 'authorization' \
            -e 'cookie' \
            -e 'endpoint=' \
            -e 'serial' \
            -e 'dsn' \
            -e 'account' \
            -e 'ssid' \
            -e 'bssid' \
            -e 'wifi' \
            -e 'wlan' \
            -e 'mac address' \
            "$SOURCE" >"$TARGET" || true
    else
        : >"$TARGET"
    fi
}

{
    echo 'Kanki redacted diagnostic bundle'
    echo "created=$STAMP"
    echo 'collection_included=no'
    echo 'config_included=no'
    echo 'credentials_included=no'
    echo 'raw_card_capture_included=no'
    echo 'renderer_metrics_included=yes_if_available'
    echo
    echo 'Raw HTML/CSS capture is opt-in via enable-render-capture and remains under'
    echo 'extensions/kanki/render-debug. It is intentionally NOT copied into this'
    echo 'redacted bundle because it may contain note content.'
} >"$WORK/README.txt"

copy_if_readable "$DIR/BUILD.json" "$WORK/BUILD.json"
copy_if_readable "$DIR/MANIFEST.sha256" "$WORK/MANIFEST.sha256"
copy_if_readable "$DIR/INSTALL.md" "$WORK/INSTALL.md"
copy_if_readable "$RENDER_DEBUG/metrics.log" "$WORK/renderer-metrics.log"
redact_log "$LOG" "$WORK/kanki.redacted.log"

{
    echo '== uname =='
    uname -a 2>/dev/null || true
    echo
    echo '== kernel =='
    uname -r 2>/dev/null || true
    echo
    echo '== selected system files =='
    for file in /etc/os-release /etc/pretty_version /etc/version; do
        if [ -r "$file" ]; then
            echo "-- $file --"
            grep -vi -e 'serial' -e 'dsn' -e 'account' -e 'ssid' -e 'wifi' "$file" 2>/dev/null || true
        fi
    done
    echo
    echo '== Kanki process state =='
    if [ -r "$DIR/.kanki.lock/pid" ]; then
        PID=$(cat "$DIR/.kanki.lock/pid" 2>/dev/null || true)
        if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
            echo 'launcher=running'
        else
            echo 'launcher=stale-lock'
        fi
    else
        echo 'launcher=not-running-or-no-lock'
    fi
    if [ -r "$DIR/.audio.pid" ]; then
        AUDIO_PID=$(cat "$DIR/.audio.pid" 2>/dev/null || true)
        if [ -n "$AUDIO_PID" ] && kill -0 "$AUDIO_PID" 2>/dev/null; then
            echo 'audio=running'
        else
            echo 'audio=stale-pid'
        fi
    else
        echo 'audio=not-running-or-no-pid'
    fi
    if [ -r "$DIR/.diag.pid" ]; then
        DIAG_PID=$(cat "$DIR/.diag.pid" 2>/dev/null || true)
        if [ -n "$DIAG_PID" ] && kill -0 "$DIAG_PID" 2>/dev/null; then
            echo 'diagnostics=running'
        else
            echo 'diagnostics=stale-pid'
        fi
    else
        echo 'diagnostics=not-running-or-no-pid'
    fi
    if [ -d "$RENDER_DEBUG" ]; then
        echo 'render_debug_dir=present'
    else
        echo 'render_debug_dir=missing'
    fi
    if [ -f "$DIR/enable-render-capture" ]; then
        echo 'raw_render_capture=enabled'
    else
        echo 'raw_render_capture=disabled'
    fi
} >"$WORK/system.txt"

{
    echo '== packaged-file integrity =='
    if [ -r "$DIR/MANIFEST.sha256" ] && command -v sha256sum >/dev/null 2>&1; then
        (cd "$DIR" && sha256sum -c MANIFEST.sha256) 2>&1 || true
    else
        echo 'manifest-check=unavailable'
    fi
    echo
    echo '== executable identity =='
    for file in libanki-kanki.so kanki-device kanki-sync kanki-diag kanki-raise kanki-audio kanki-gst-play; do
        if [ -r "$DIR/$file" ] && command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$DIR/$file"
        fi
    done
} >"$WORK/integrity.txt"

# Never copy config.ini, collection.anki2, collection.media, raw render captures,
# browser history, account files, Wi-Fi configuration or Kindle identifiers into
# the default report. `renderer-metrics.log` contains geometry/style metadata but
# deliberately contains no element text.
if command -v tar >/dev/null 2>&1; then
    (cd "$OUT_ROOT" && tar -czf "$ARCHIVE" "$(basename "$WORK")")
else
    echo "kanki-report: tar is unavailable; report directory left at $WORK" >&2
    exit 69
fi

rm -rf "$WORK"
printf 'Kanki report created: %s\n' "$ARCHIVE"
