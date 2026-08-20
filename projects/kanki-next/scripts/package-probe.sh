#!/bin/sh
set -eu

PROJECT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
BINARY=${1:-"$PROJECT/build/kanki-next-render-probe-armhf"}
DIST=${2:-"$PROJECT/build/dist"}
case "$BINARY" in
    /*) ;;
    *) BINARY="$PROJECT/$BINARY" ;;
esac
case "$DIST" in
    /*) ;;
    *) DIST="$PROJECT/$DIST" ;;
esac
COMMIT=${KANKI_NEXT_COMMIT:-unknown}
TOOLCHAIN=${KANKI_NEXT_TOOLCHAIN:-unknown}

if [ ! -x "$BINARY" ]; then
    echo "missing executable probe binary: $BINARY" >&2
    exit 2
fi

STAGE="$DIST/stage"
EXT="$STAGE/kanki-next"
rm -rf "$DIST"
mkdir -p "$EXT"

cp "$BINARY" "$EXT/kanki-next-render-probe-armhf"
cp "$PROJECT/scripts/launch-probe.sh" "$EXT/launch-probe.sh"
cp "$PROJECT/scripts/collect-device-report.sh" "$EXT/collect-device-report.sh"
cp "$PROJECT/package/menu.json" "$EXT/menu.json"
cp "$PROJECT/package/README.txt" "$EXT/README.txt"
chmod +x \
    "$EXT/kanki-next-render-probe-armhf" \
    "$EXT/launch-probe.sh" \
    "$EXT/collect-device-report.sh"

{
    echo "KANKI_NEXT_RENDER_PROBE_BUILD_V1"
    echo "commit=$COMMIT"
    echo "toolchain=$TOOLCHAIN"
    echo "built_utc=${KANKI_NEXT_BUILT_UTC:-unknown}"
} >"$EXT/BUILD.txt"

(
    cd "$STAGE"
    zip -qr "$DIST/kanki-next-render-probe.zip" kanki-next
)
sha256sum "$DIST/kanki-next-render-probe.zip" >"$DIST/kanki-next-render-probe.zip.sha256"

rm -rf "$STAGE"
printf '%s\n' "$DIST/kanki-next-render-probe.zip"
