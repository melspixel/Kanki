#!/bin/sh
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
LOG="$HERE/launcher.log"
BIN="$HERE/kanki-next-render-probe-armhf"

{
    echo "KANKI_NEXT_PROBE_LAUNCH_V1"
    date 2>/dev/null || true
    uname -a 2>/dev/null || true
    if [ ! -x "$BIN" ]; then
        echo "missing executable: $BIN"
        exit 1
    fi
    exec "$BIN"
} >>"$LOG" 2>&1
