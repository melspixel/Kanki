#!/usr/bin/env bash
set -euo pipefail

ROOT=${1:?usage: audit_kindlerootfs.sh ROOTFS_MOUNT OUTPUT_DIR}
OUT=${2:?usage: audit_kindlerootfs.sh ROOTFS_MOUNT OUTPUT_DIR}
mkdir -p "$OUT"

section() {
    printf '\n===== %s =====\n' "$1"
}

report_one() {
    local f="$1"
    [ -e "$f" ] || [ -L "$f" ] || return 0
    echo "PATH ${f#$ROOT}"
    ls -ld "$f" || true
    if [ -f "$f" ]; then
        file "$f" || true
        sha256sum "$f" || true
        readelf -h "$f" 2>/dev/null | sed -n '1,24p' || true
        echo "NEEDED:"
        readelf -d "$f" 2>/dev/null | grep -E 'NEEDED|SONAME|RPATH|RUNPATH' || true
        echo "VERSIONS:"
        readelf --version-info "$f" 2>/dev/null | grep -oE '(GLIBC|GLIBCXX|GCC)_[0-9.]+' | sort -Vu | tail -30 || true
        echo "VERSION STRINGS:"
        strings "$f" 2>/dev/null | grep -Ei 'webkit|javascriptcore|gtk\+|gtk [0-9]|glib [0-9]|pango [0-9]|fontconfig|freetype|gstreamer|libsoup' | head -80 || true
    fi
    echo
}

{
    echo "KANKI_KINDLE_ROOTFS_AUDIT_V1"
    echo "generated_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    section "VERSION FILES"
    for f in "$ROOT/etc/prettyversion.txt" "$ROOT/etc/version.txt" "$ROOT/etc/os-release" "$ROOT/etc/issue"; do
        if [ -r "$f" ]; then
            echo "--- ${f#$ROOT} ---"
            sed -n '1,100p' "$f" || true
        fi
    done

    section "ABI BASELINE"
    for f in \
        "$ROOT/lib/ld-linux-armhf.so.3" \
        "$ROOT/lib/ld-linux.so.3" \
        "$ROOT/lib/libc.so.6" \
        "$ROOT/lib/libm.so.6" \
        "$ROOT/lib/libpthread.so.0" \
        "$ROOT/lib/libdl.so.2"; do
        report_one "$f"
    done

    section "WEBKIT GTK JSCORE"
    find "$ROOT/usr/lib" "$ROOT/lib" -maxdepth 1 \( \
        -name 'libwebkit*' -o -name 'libjavascriptcore*' -o \
        -name 'libgtk*' -o -name 'libgdk*' -o -name 'libsoup*' \) \
        -print 2>/dev/null | sort | while IFS= read -r f; do report_one "$f"; done

    section "TEXT AND FONT STACK"
    find "$ROOT/usr/lib" "$ROOT/lib" -maxdepth 1 \( \
        -name 'libglib-2.0*' -o -name 'libgobject-2.0*' -o \
        -name 'libpango*' -o -name 'libfontconfig*' -o -name 'libfreetype*' -o \
        -name 'libharfbuzz*' \) -print 2>/dev/null | sort | while IFS= read -r f; do report_one "$f"; done

    section "GSTREAMER CORE"
    find "$ROOT/usr/lib" "$ROOT/lib" -maxdepth 1 -name 'libgst*' -print 2>/dev/null | sort | while IFS= read -r f; do report_one "$f"; done

    section "GSTREAMER PLUGINS"
    for d in "$ROOT/usr/lib/gstreamer-1.0" "$ROOT/usr/lib/gstreamer-0.10"; do
        [ -d "$d" ] || continue
        echo "DIRECTORY ${d#$ROOT}"
        find "$d" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | sort
    done

    section "FONTS"
    for d in "$ROOT/usr/share/fonts" "$ROOT/usr/java/lib/fonts"; do
        [ -d "$d" ] || continue
        echo "DIRECTORY ${d#$ROOT}"
        find "$d" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -printf '%P\n' 2>/dev/null | sort
    done

    section "BROWSER/RENDERER EXECUTABLES"
    find "$ROOT/usr/bin" "$ROOT/usr/sbin" -maxdepth 1 -type f \( \
        -iname '*webkit*' -o -iname '*browser*' -o -iname '*mesquite*' -o -iname '*cvm*' \) \
        -print 2>/dev/null | sort | while IFS= read -r f; do report_one "$f"; done
} > "$OUT/rootfs-runtime-audit.txt"

# Compact machine-readable inventories used to compare a real-device fingerprint.
find "$ROOT/usr/lib" "$ROOT/lib" -maxdepth 1 \( \
    -name 'libwebkit*' -o -name 'libjavascriptcore*' -o -name 'libgtk*' -o \
    -name 'libgdk*' -o -name 'libglib-2.0*' -o -name 'libgobject-2.0*' -o \
    -name 'libpango*' -o -name 'libfontconfig*' -o -name 'libfreetype*' -o \
    -name 'libharfbuzz*' -o -name 'libsoup*' -o -name 'libgst*' \) \
    -type f -print0 2>/dev/null | sort -z | xargs -0 -r sha256sum > "$OUT/runtime-library-sha256.txt"

for d in "$ROOT/usr/share/fonts" "$ROOT/usr/java/lib/fonts"; do
    [ -d "$d" ] || continue
    find "$d" -type f \( -name '*.ttf' -o -name '*.otf' -o -name '*.ttc' \) -print
 done | sed "s#^$ROOT##" | sort > "$OUT/font-inventory.txt"

printf 'audit_root=%s\n' "$ROOT" > "$OUT/audit-meta.txt"
printf 'runtime_library_count=%s\n' "$(wc -l < "$OUT/runtime-library-sha256.txt")" >> "$OUT/audit-meta.txt"
printf 'font_count=%s\n' "$(wc -l < "$OUT/font-inventory.txt")" >> "$OUT/audit-meta.txt"
