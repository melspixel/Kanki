#!/bin/sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
OUT="$DIR/Kindle-Anki-Port-source.zip"

if base64 --help 2>&1 | grep -q -- '--decode'; then
    cat "$DIR"/part-* | base64 --decode > "$OUT"
elif base64 -d </dev/null >/dev/null 2>&1; then
    cat "$DIR"/part-* | base64 -d > "$OUT"
else
    cat "$DIR"/part-* | base64 -D > "$OUT"
fi

EXPECTED=$(awk 'NR==1 {print $1}' "$DIR/Kindle-Anki-Port-source.zip.sha256")
if command -v sha256sum >/dev/null 2>&1; then
    ACTUAL=$(sha256sum "$OUT" | awk '{print $1}')
else
    ACTUAL=$(shasum -a 256 "$OUT" | awk '{print $1}')
fi

[ "$EXPECTED" = "$ACTUAL" ] || {
    printf '%s\n' "SHA-256 mismatch: expected $EXPECTED, got $ACTUAL" >&2
    rm -f "$OUT"
    exit 1
}

printf '%s\n' "Restored and verified: $OUT"
