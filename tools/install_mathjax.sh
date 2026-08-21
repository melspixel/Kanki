#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VERSION=2.7.9
SHA256=7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786
URL=${KANKI_MATHJAX_URL:-https://registry.npmjs.org/mathjax/-/mathjax-2.7.9.tgz}
DEST=${1:-$ROOT/out/host-mathjax/mathjax-$VERSION}
CACHE_DIR=${KANKI_MATHJAX_CACHE:-$ROOT/out/vendor-cache}
ARCHIVE=$CACHE_DIR/mathjax-$VERSION.tgz
DOWNLOAD=$ARCHIVE.download.$$

case "$DEST" in
    "$ROOT"/out/?*) ;;
    *)
        echo "kanki-mathjax: destination must be a child of $ROOT/out" >&2
        exit 64
        ;;
esac

for command in curl python3 tar; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "kanki-mathjax: required command missing: $command" >&2
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
    while True:
        chunk = source.read(1024 * 1024)
        if not chunk:
            break
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
    curl -fL --retry 3 "$URL" -o "$DOWNLOAD"
    if ! verify_archive "$DOWNLOAD"; then
        echo "kanki-mathjax: archive checksum mismatch" >&2
        exit 65
    fi
    mv "$DOWNLOAD" "$ARCHIVE"
    trap - EXIT INT TERM
fi

rm -rf "$DEST"
mkdir -p "$DEST"
tar -xzf "$ARCHIVE" --strip-components=1 -C "$DEST" \
    package/MathJax.js package/LICENSE package/config package/extensions \
    package/jax package/localization
test -f "$DEST/MathJax.js"
test -f "$DEST/config/TeX-AMS_SVG-full.js"
test -f "$DEST/jax/output/SVG/jax.js"
test -f "$DEST/LICENSE"

printf 'KANKI_MATHJAX_VERSION=%s\n' "$VERSION"
printf 'KANKI_MATHJAX_SHA256=%s\n' "$SHA256"
printf 'KANKI_MATHJAX_ROOT=%s\n' "$DEST"
