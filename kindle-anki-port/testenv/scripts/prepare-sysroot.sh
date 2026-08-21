#!/bin/sh
set -eu
ROOTFS=${1:?usage: prepare-sysroot.sh ROOTFS EXPECTED_MANIFEST_SHA256 OUTPUT_MANIFEST}
EXPECTED=${2:?}
MANIFEST=${3:?}
[ -d "$ROOTFS" ] || {
    echo "rootfs directory not found: $ROOTFS" >&2
    exit 2
}
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT
find "$ROOTFS" -type f -print0 | sort -z | xargs -0 sha256sum > "$TMP"
ACTUAL=$(sha256sum "$TMP" | awk '{print $1}')
[ "$ACTUAL" = "$EXPECTED" ] || {
    echo "rootfs manifest hash mismatch: expected $EXPECTED, got $ACTUAL" >&2
    exit 3
}
python3 - "$ROOTFS" "$EXPECTED" "$MANIFEST" <<'PY'
import json
import sys
from pathlib import Path
rootfs, digest, output = sys.argv[1:]
data = {
    "schema": 1,
    "rootfs": str(Path(rootfs).resolve()),
    "manifest_sha256": digest,
    "dynamic_linker": "/lib/ld-linux-armhf.so.3",
}
Path(output).write_text(json.dumps(data, indent=2) + "\n")
PY
