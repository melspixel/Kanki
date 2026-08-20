#!/bin/sh
set -u

HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT=/mnt/us/documents/KankiNextProbeReport.txt
TMP="${OUT}.tmp"

write_file() {
    LABEL=$1
    PATHNAME=$2
    echo "===== $LABEL ====="
    if [ -r "$PATHNAME" ]; then
        cat "$PATHNAME"
    else
        echo "unavailable: $PATHNAME"
    fi
    echo
}

{
    echo "KANKI_NEXT_DEVICE_REPORT_V1"
    date 2>/dev/null || true
    echo
    echo "===== safe system identity ====="
    uname -a 2>/dev/null || true
    for version_file in /etc/prettyversion.txt /etc/version.txt /etc/os-release; do
        if [ -r "$version_file" ]; then
            echo "--- $version_file ---"
            cat "$version_file"
        fi
    done
    echo
    echo "===== framebuffer ====="
    if command -v fbset >/dev/null 2>&1; then
        fbset 2>/dev/null || true
    fi
    if [ -r /sys/class/graphics/fb0/virtual_size ]; then
        cat /sys/class/graphics/fb0/virtual_size
    fi
    echo
    echo "===== renderer libraries ====="
    for lib in \
        /usr/lib/libwebkitgtk-1.0.so.0 \
        /usr/lib/libgtk-x11-2.0.so.0 \
        /lib/libc.so.6 \
        /lib/arm-linux-gnueabihf/libc.so.6; do
        if [ -e "$lib" ]; then
            ls -l "$lib" 2>/dev/null || true
            if command -v sha256sum >/dev/null 2>&1; then
                sha256sum "$lib" 2>/dev/null || true
            fi
        fi
    done
    echo
    write_file "renderer probe" "$HERE/render-probe.log"
    write_file "launcher" "$HERE/launcher.log"
    echo "===== package build ====="
    if [ -r "$HERE/BUILD.txt" ]; then
        cat "$HERE/BUILD.txt"
    else
        echo "BUILD.txt unavailable"
    fi
} >"$TMP" 2>&1

mv "$TMP" "$OUT"
echo "Wrote $OUT"
