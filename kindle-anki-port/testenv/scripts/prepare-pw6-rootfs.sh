#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT=$(CDPATH= cd -- "$SCRIPT_DIR/../.." && pwd)
MANIFEST=${KAP_PW6_MANIFEST:-"$PROJECT/testenv/qemu/pw6-5.19.6-rootfs-manifest.json"}
KINDLETOOL=${KINDLETOOL:-kindletool}
FIRMWARE=''
OUTPUT=''
KEEP_IMAGE=0
DOWNLOAD=0

AMAZON_ALIAS='https://www.amazon.com/update_KindlePaperwhite_12th_Gen_2024'
AMAZON_OBJECT='https://s3.amazonaws.com/firmwaredownloads/update_kindle_all_new_paperwhite_12th_5.19.6.bin'
COMMUNITY_MIRROR='https://files.cocaine.trade/firmware/kindle/PW6/update_kindle_all_new_paperwhite_12th_5.19.6.bin'

usage() {
    cat <<EOF
Usage:
  $0 --firmware FILE --output ROOTFS_DIR [--manifest FILE] [--kindletool FILE] [--keep-image]
  $0 --download --firmware FILE --output ROOTFS_DIR [options]
  $0 --print-sources

The script verifies the pinned PW6 5.19.6 firmware, extracts it with
KindleTool, verifies rootfs.img, expands the ext filesystem with debugfs, and
runs verify-pw6-rootfs.py. Firmware/rootfs bytes remain external private test
inputs and are never copied into the Git repository.
EOF
}

sha256_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

manifest_value() {
    python3 - "$MANIFEST" "$1" <<'PY'
import json, sys
value=json.load(open(sys.argv[1], encoding='utf-8'))
for part in sys.argv[2].split('.'):
    value=value[part]
print(value)
PY
}

fail() {
    printf '%s\n' "FAIL: $*" >&2
    exit 1
}

print_sources() {
    cat <<EOF
Amazon alias: $AMAZON_ALIAS
Amazon object: $AMAZON_OBJECT
Community mirror: $COMMUNITY_MIRROR
Expected firmware SHA-256: $(manifest_value firmware.package_sha256)
Expected rootfs image SHA-256: $(manifest_value rootfs_image.sha256)
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --firmware) [ $# -ge 2 ] || fail '--firmware requires a path'; FIRMWARE=$2; shift 2;;
        --output) [ $# -ge 2 ] || fail '--output requires a path'; OUTPUT=$2; shift 2;;
        --manifest) [ $# -ge 2 ] || fail '--manifest requires a path'; MANIFEST=$2; shift 2;;
        --kindletool) [ $# -ge 2 ] || fail '--kindletool requires a path'; KINDLETOOL=$2; shift 2;;
        --download) DOWNLOAD=1; shift;;
        --keep-image) KEEP_IMAGE=1; shift;;
        --print-sources) print_sources; exit 0;;
        -h|--help) usage; exit 0;;
        *) fail "unknown argument: $1";;
    esac
done

[ -f "$MANIFEST" ] || fail "manifest not found: $MANIFEST"
[ -n "$FIRMWARE" ] || fail '--firmware is required'
[ -n "$OUTPUT" ] || fail '--output is required'

EXPECTED_FIRMWARE=$(manifest_value firmware.package_sha256)
EXPECTED_ROOTFS=$(manifest_value rootfs_image.sha256)

if [ "$DOWNLOAD" -eq 1 ] && [ ! -f "$FIRMWARE" ]; then
    command -v curl >/dev/null 2>&1 || fail 'curl is required for --download'
    mkdir -p "$(dirname -- "$FIRMWARE")"
    TMP_DOWNLOAD="$FIRMWARE.part.$$"
    trap 'rm -f "$TMP_DOWNLOAD"' EXIT HUP INT TERM
    if ! curl -fL --retry 4 --connect-timeout 30 "$AMAZON_ALIAS" -o "$TMP_DOWNLOAD"; then
        printf '%s\n' 'Amazon alias failed; trying the pinned community mirror.' >&2
        curl -fL --retry 4 --connect-timeout 30 "$COMMUNITY_MIRROR" -o "$TMP_DOWNLOAD" \
            || fail 'unable to download the pinned firmware from configured sources'
    fi
    mv "$TMP_DOWNLOAD" "$FIRMWARE"
    trap - EXIT HUP INT TERM
fi

[ -f "$FIRMWARE" ] || fail "firmware not found: $FIRMWARE"
ACTUAL_FIRMWARE=$(sha256_file "$FIRMWARE")
[ "$ACTUAL_FIRMWARE" = "$EXPECTED_FIRMWARE" ] || \
    fail "firmware SHA-256 mismatch: expected $EXPECTED_FIRMWARE, got $ACTUAL_FIRMWARE"

command -v python3 >/dev/null 2>&1 || fail 'python3 is required'
command -v gzip >/dev/null 2>&1 || fail 'gzip is required'
command -v debugfs >/dev/null 2>&1 || fail 'debugfs (e2fsprogs) is required'
if [ -x "$KINDLETOOL" ]; then :; elif command -v "$KINDLETOOL" >/dev/null 2>&1; then
    KINDLETOOL=$(command -v "$KINDLETOOL")
else
    fail "KindleTool not found: $KINDLETOOL"
fi

if [ -e "$OUTPUT" ]; then
    [ -d "$OUTPUT" ] || fail "output exists and is not a directory: $OUTPUT"
    [ -z "$(find "$OUTPUT" -mindepth 1 -maxdepth 1 -print -quit)" ] || \
        fail "output directory is not empty: $OUTPUT"
else
    mkdir -p "$OUTPUT"
fi
OUTPUT=$(CDPATH= cd -- "$OUTPUT" && pwd)

TMP_ROOT=${TMPDIR:-/tmp}/kap-pw6-rootfs.$$
EXTRACTED="$TMP_ROOT/extracted"
ROOTFS_IMAGE="$TMP_ROOT/pw6-rootfs.img"
REPORT="$OUTPUT/../pw6-rootfs-preparation-report.txt"
mkdir -p "$EXTRACTED"
cleanup() {
    if [ "$KEEP_IMAGE" -eq 1 ] && [ -f "$ROOTFS_IMAGE" ]; then
        cp -p "$ROOTFS_IMAGE" "$OUTPUT/../pw6-rootfs.img"
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT HUP INT TERM

"$KINDLETOOL" extract "$FIRMWARE" "$EXTRACTED"
ROOTFS_GZ=$(find "$EXTRACTED" -type f -name 'rootfs.img.gz' -print -quit)
[ -n "$ROOTFS_GZ" ] || fail 'KindleTool output did not contain rootfs.img.gz'
gzip -dc "$ROOTFS_GZ" > "$ROOTFS_IMAGE"
ACTUAL_ROOTFS=$(sha256_file "$ROOTFS_IMAGE")
[ "$ACTUAL_ROOTFS" = "$EXPECTED_ROOTFS" ] || \
    fail "rootfs image SHA-256 mismatch: expected $EXPECTED_ROOTFS, got $ACTUAL_ROOTFS"

debugfs -R "rdump / $OUTPUT" "$ROOTFS_IMAGE" >/dev/null 2>&1
python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" \
    "$OUTPUT" --manifest "$MANIFEST" --rootfs-image "$ROOTFS_IMAGE" | tee "$REPORT"

{
    printf '%s\n' 'KAP_PW6_ROOTFS_PREPARATION_V1'
    printf 'firmware=%s\n' "$FIRMWARE"
    printf 'firmware_sha256=%s\n' "$ACTUAL_FIRMWARE"
    printf 'rootfs_image_sha256=%s\n' "$ACTUAL_ROOTFS"
    printf 'rootfs_directory=%s\n' "$OUTPUT"
    printf 'kindletool=%s\n' "$KINDLETOOL"
} >> "$REPORT"

printf '%s\n' "Prepared and verified PW6 rootfs at $OUTPUT"
