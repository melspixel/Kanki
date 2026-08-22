#!/bin/sh
# Bounded, non-sensitive runtime fingerprint used to match a real device
# against an extracted Amazon firmware rootfs. It deliberately avoids user
# data, network configuration, serial numbers and account information.

OUT=${1:-/mnt/us/extensions/ranki/system-fingerprint.txt}
TMP="${OUT}.tmp.$$"

emit_file() {
    f="$1"
    if [ -r "$f" ]; then
        echo "--- FILE $f ---"
        sed -n '1,80p' "$f" 2>/dev/null || cat "$f" 2>/dev/null || true
    fi
}

emit_path() {
    f="$1"
    [ -e "$f" ] || [ -L "$f" ] || return 0
    echo "--- PATH $f ---"
    ls -ld "$f" 2>/dev/null || true
    if command -v md5sum >/dev/null 2>&1 && [ -f "$f" ]; then
        md5sum "$f" 2>/dev/null || true
    elif command -v sha256sum >/dev/null 2>&1 && [ -f "$f" ]; then
        sha256sum "$f" 2>/dev/null || true
    fi
}

{
    echo "KANKI_SYSTEM_FINGERPRINT_V1"
    echo "captured_at=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || echo unknown)"
    echo "uname=$(uname -a 2>/dev/null || echo unknown)"
    echo "machine=$(uname -m 2>/dev/null || echo unknown)"

    emit_file /etc/prettyversion.txt
    emit_file /etc/version.txt
    emit_file /etc/os-release
    emit_file /etc/issue

    echo "--- CPU ---"
    grep -E '^(model name|Processor|Hardware|Features|CPU architecture|BogoMIPS)' /proc/cpuinfo 2>/dev/null | head -40 || true
    echo "--- FRAMEBUFFER ---"
    for f in /sys/class/graphics/fb0/virtual_size /sys/class/graphics/fb0/bits_per_pixel /sys/class/graphics/fb0/name; do
        [ -r "$f" ] && echo "$f=$(cat "$f" 2>/dev/null)"
    done

    # Loader/libc establish the ABI baseline.
    for f in \
        /lib/ld-linux-armhf.so.3 \
        /lib/ld-linux.so.3 \
        /lib/libc.so.6 \
        /lib/libm.so.6 \
        /lib/libpthread.so.0 \
        /lib/libdl.so.2; do
        emit_path "$f"
    done

    echo "--- RENDER STACK LIBRARIES ---"
    for d in /usr/lib /lib; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 \( \
            -name 'libwebkit*' -o -name 'libjavascriptcore*' -o \
            -name 'libgtk*' -o -name 'libgdk*' -o -name 'libglib-2.0*' -o \
            -name 'libgobject-2.0*' -o -name 'libpango*' -o \
            -name 'libfontconfig*' -o -name 'libfreetype*' \) \
            -print 2>/dev/null | sort | while IFS= read -r f; do emit_path "$f"; done
    done

    echo "--- GSTREAMER STACK ---"
    for d in /usr/lib/gstreamer-1.0 /usr/lib/gstreamer-0.10; do
        [ -d "$d" ] || continue
        echo "directory=$d"
        find "$d" -maxdepth 1 -type f -print 2>/dev/null | sort | head -160
    done

    echo "--- FONT FILES ---"
    for d in /usr/share/fonts /usr/java/lib/fonts /mnt/us/fonts; do
        [ -d "$d" ] || continue
        echo "directory=$d"
        find "$d" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -print 2>/dev/null | sort | head -240
    done

    echo "--- WEBKIT/GTK EXECUTABLE HINTS ---"
    for d in /usr/bin /usr/sbin; do
        [ -d "$d" ] || continue
        find "$d" -maxdepth 1 -type f \( -name '*webkit*' -o -name '*browser*' -o -name '*mesquite*' \) -print 2>/dev/null | sort | head -80
    done
} >"$TMP" 2>/dev/null

mv "$TMP" "$OUT" 2>/dev/null || { cat "$TMP" >"$OUT" 2>/dev/null; rm -f "$TMP"; }
exit 0
