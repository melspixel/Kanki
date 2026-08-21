#!/bin/sh
set -eu

# Canonical prebuilt KHF toolchain used by Kanki CI/release builds.
# Do not replace this with a `releases/latest` URL: release candidates must be
# reproducible from repository state alone.
KOX_VERSION=2026.08
KOX_SHA256=8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0
KOX_URL="https://github.com/koreader/koxtoolchain/releases/download/${KOX_VERSION}/kindlehf.tar.zst"
DEST=${1:-"$HOME"}
ARCHIVE=${TMPDIR:-/tmp}/kanki-kindlehf-${KOX_VERSION}.tar.zst

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "kanki-toolchain: required command missing: $1" >&2
        exit 69
    }
}

need curl
need sha256sum
need tar
need zstd

mkdir -p "$DEST"
rm -f "$ARCHIVE"
echo "kanki-toolchain: download koxtoolchain ${KOX_VERSION}" >&2
curl -fL --retry 3 --retry-delay 2 "$KOX_URL" -o "$ARCHIVE"
printf '%s  %s\n' "$KOX_SHA256" "$ARCHIVE" | sha256sum -c -

tar --zstd -xf "$ARCHIVE" -C "$DEST"
TC="$DEST/x-tools/arm-kindlehf-linux-gnueabihf"
CC="$TC/bin/arm-kindlehf-linux-gnueabihf-gcc"
if [ ! -x "$CC" ]; then
    echo "kanki-toolchain: compiler missing after extraction: $CC" >&2
    exit 70
fi

printf 'KANKI_KOX_VERSION=%s\n' "$KOX_VERSION"
printf 'KANKI_KOX_SHA256=%s\n' "$KOX_SHA256"
printf 'KANKI_KOX_ROOT=%s\n' "$TC"
