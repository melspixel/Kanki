#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
DEST=${1:-$ROOT/out/host-node}
NODE_ROOT=${2:-}
LOCK_SHA256=099baf5da82f868995429854eb878fea8d4ed78c22875d4436e48e466e47490f
SOURCE=$ROOT/tools/host-node

case "$DEST" in
    "$ROOT"/out/?*) ;;
    *)
        echo "kanki-host-jsdom: destination must be a child of $ROOT/out" >&2
        exit 64
        ;;
esac

if [ -n "$NODE_ROOT" ]; then
    NODE_BIN=$NODE_ROOT/bin/node
    NPM_BIN=$NODE_ROOT/bin/npm
else
    NODE_BIN=${NODE_BIN:-$(command -v node || true)}
    NPM_BIN=${NPM_BIN:-$(command -v npm || true)}
fi
for command in python3 cp cmp; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "kanki-host-jsdom: required command missing: $command" >&2
        exit 69
    }
done
if [ -z "$NODE_BIN" ] || [ ! -x "$NODE_BIN" ] || [ -z "$NPM_BIN" ] || [ ! -x "$NPM_BIN" ]; then
    echo "kanki-host-jsdom: Node.js and npm are required" >&2
    exit 69
fi

python3 - "$SOURCE/package-lock.json" "$LOCK_SHA256" <<'PY'
from hashlib import sha256
from pathlib import Path
import sys

path = Path(sys.argv[1])
expected = sys.argv[2]
digest = sha256(path.read_bytes()).hexdigest()
if digest != expected:
    raise SystemExit("kanki-host-jsdom: package lock checksum mismatch")
PY

if ! cmp -s "$SOURCE/package.json" "$DEST/package.json" \
    || ! cmp -s "$SOURCE/package-lock.json" "$DEST/package-lock.json" \
    || ! NODE_PATH="$DEST/node_modules" "$NODE_BIN" -e 'require("jsdom")' >/dev/null 2>&1; then
    rm -rf "$DEST"
    mkdir -p "$DEST"
    cp "$SOURCE/package.json" "$SOURCE/package-lock.json" "$DEST/"
    PATH="$(dirname "$NODE_BIN"):$PATH" "$NPM_BIN" ci \
        --prefix "$DEST" --cache "$ROOT/out/npm-cache" \
        --ignore-scripts --no-audit --no-fund >/dev/null
fi

NODE_PATH="$DEST/node_modules" "$NODE_BIN" -e \
    'if(require("jsdom/package.json").version!=="24.1.3") process.exit(1)'
printf 'KANKI_JSDOM_VERSION=24.1.3\n'
printf 'KANKI_JSDOM_LOCK_SHA256=%s\n' "$LOCK_SHA256"
printf 'KANKI_JSDOM_ROOT=%s\n' "$DEST/node_modules"
