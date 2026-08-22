#!/bin/sh
set -eu

# Host-test runtime only. This is never copied into the Kindle package.
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=20.18.2
DEST=${1:-$ROOT/out/host-node-toolchain/node-v$VERSION}
CACHE_DIR=${KANKI_NODE_CACHE:-$ROOT/out/vendor-cache}

case "$(uname -s):$(uname -m)" in
    Linux:x86_64)
        PLATFORM=linux-x64
        EXTENSION=tar.xz
        SHA256=4e50f727ae09bdafecf2322c72faf7cd82bf3b8851a16b8bb63974e0d8d6eceb
        ;;
    Linux:aarch64|Linux:arm64)
        PLATFORM=linux-arm64
        EXTENSION=tar.xz
        SHA256=5c1437aa16e7e6a2e0687a42c4d3f0a8f8a2039cda8880cb3be8cd983aeefb44
        ;;
    Darwin:x86_64)
        PLATFORM=darwin-x64
        EXTENSION=tar.gz
        SHA256=00a16bb0a82a2ad5d00d66b466ae1afa678482283747c27e9bce96668f334744
        ;;
    Darwin:arm64)
        PLATFORM=darwin-arm64
        EXTENSION=tar.gz
        SHA256=fa76d5b5340f14070ebaa88ef8faa28c1e9271502725e830cb52f0cf5b6493de
        ;;
    *)
        echo "kanki-host-node: unsupported host: $(uname -s) $(uname -m)" >&2
        exit 70
        ;;
esac

case "$DEST" in
    "$ROOT"/out/?*) ;;
    *)
        echo "kanki-host-node: destination must be a child of $ROOT/out" >&2
        exit 64
        ;;
esac

ARCHIVE_NAME=node-v${VERSION}-${PLATFORM}.${EXTENSION}
URL=${KANKI_NODE_URL:-https://nodejs.org/dist/v${VERSION}/${ARCHIVE_NAME}}
ARCHIVE=$CACHE_DIR/$ARCHIVE_NAME
DOWNLOAD=$ARCHIVE.download.$$

for command in curl python3 tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "kanki-host-node: required command missing: $command" >&2
        exit 69
    }
done

verify_archive() {
    python3 - "$1" "$SHA256" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

path = Path(sys.argv[1])
expected = sys.argv[2]
digest = sha256()
with path.open("rb") as source:
    for chunk in iter(lambda: source.read(1024 * 1024), b""):
        digest.update(chunk)
if digest.hexdigest() != expected:
    raise SystemExit(1)
PY
}

mkdir -p "$CACHE_DIR"
if [ -f "$ARCHIVE" ] && ! verify_archive "$ARCHIVE"; then
    rm -f "$ARCHIVE"
fi
if [ ! -f "$ARCHIVE" ]; then
    trap 'rm -f "$DOWNLOAD"' EXIT INT TERM
    curl --proto '=https' --tlsv1.2 -fL --retry 3 "$URL" -o "$DOWNLOAD"
    if ! verify_archive "$DOWNLOAD"; then
        echo "kanki-host-node: archive checksum mismatch" >&2
        exit 65
    fi
    mv "$DOWNLOAD" "$ARCHIVE"
    trap - EXIT INT TERM
fi

rm -rf "$DEST"
mkdir -p "$DEST"
case "$EXTENSION" in
    tar.xz) tar -xJf "$ARCHIVE" --strip-components=1 -C "$DEST" ;;
    tar.gz) tar -xzf "$ARCHIVE" --strip-components=1 -C "$DEST" ;;
esac
test -x "$DEST/bin/node"
test -x "$DEST/bin/npm"
test "$("$DEST/bin/node" --version)" = "v$VERSION"
PATH="$DEST/bin:$PATH" "$DEST/bin/npm" --version >/dev/null

printf 'KANKI_HOST_NODE_VERSION=%s\n' "$VERSION"
printf 'KANKI_HOST_NODE_SHA256=%s\n' "$SHA256"
printf 'KANKI_HOST_NODE_ROOT=%s\n' "$DEST"
