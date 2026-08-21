#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

ANKI_COMMIT=${ANKI_COMMIT:-e5a6fbe27fdd4d57d5f712191b4a753032e57853}
OUT_DIR=${KANKI_HOST_BRIDGE_OUT_DIR:-$ROOT/out/host-anki}
BUILD_COMMIT=${KANKI_BUILD_COMMIT:-$(git rev-parse HEAD)}
PROTOC=${PROTOC:-$(command -v protoc || true)}

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "kanki-host-anki: required command missing: $1" >&2
        exit 69
    }
}

for command in git cargo rustc python3 gcc nm readelf sha256sum realpath mktemp; do
    need "$command"
done
if [ -z "$PROTOC" ] || [ ! -x "$PROTOC" ]; then
    echo "kanki-host-anki: protoc is required" >&2
    exit 69
fi
if ! rustc --version | grep -q '^rustc 1\.92\.0 '; then
    echo "kanki-host-anki: rustc 1.92.0 required; found: $(rustc --version)" >&2
    exit 70
fi
if [ "$(uname -s)" != Linux ]; then
    echo "kanki-host-anki: this ABI smoke recipe requires a Linux host" >&2
    exit 70
fi
if [ "${KANKI_ALLOW_DIRTY:-0}" != 1 ]; then
    if ! git diff --quiet --ignore-submodules=dirty \
        || ! git diff --cached --quiet --ignore-submodules=dirty; then
        echo "kanki-host-anki: repository has uncommitted changes; commit them or set KANKI_ALLOW_DIRTY=1" >&2
        exit 71
    fi
fi
if [ "$(git -C third_party/anki rev-parse HEAD)" != "$ANKI_COMMIT" ]; then
    echo "kanki-host-anki: Anki gitlink does not match $ANKI_COMMIT" >&2
    exit 72
fi

SCRATCH=$(mktemp -d /tmp/kanki-host-anki.XXXXXX)
SYNC_SERVER_PID=
ANKI_LIB_RS=third_party/anki/rslib/src/lib.rs
ANKI_CARGO=third_party/anki/rslib/Cargo.toml
ANKI_BRIDGE_RS=third_party/anki/rslib/src/kanki_bridge.rs
ANKI_SYNC_RS=third_party/anki/rslib/src/kanki_sync_bridge.rs
ANKI_FIXTURE_RS=third_party/anki/rslib/src/bin/kanki_fixture.rs
cp "$ANKI_LIB_RS" "$SCRATCH/lib.rs.original"
cp "$ANKI_CARGO" "$SCRATCH/Cargo.toml.original"

cleanup() {
    if [ -n "$SYNC_SERVER_PID" ]; then
        kill "$SYNC_SERVER_PID" 2>/dev/null || true
        wait "$SYNC_SERVER_PID" 2>/dev/null || true
    fi
    cp "$SCRATCH/lib.rs.original" "$ANKI_LIB_RS" 2>/dev/null || true
    cp "$SCRATCH/Cargo.toml.original" "$ANKI_CARGO" 2>/dev/null || true
    rm -f "$ANKI_BRIDGE_RS" "$ANKI_SYNC_RS" "$ANKI_FIXTURE_RS"
    rmdir third_party/anki/rslib/src/bin 2>/dev/null || true
    rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/bridge-smoke.txt" "$OUT_DIR/bridge-integration.txt" \
      "$OUT_DIR/sync-integration.txt" \
      "$OUT_DIR/bridge-exports.txt" \
      "$OUT_DIR/bridge-dynamic.txt" "$OUT_DIR/bridge-library.sha256"

printf '%s\n' '== initialize pinned Anki translations =='
git -C third_party/anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
mkdir -p third_party/anki/out/rslib/proto third_party/anki/out/extracted/protoc/bin
ln -sf "$PROTOC" third_party/anki/out/extracted/protoc/bin/protoc

printf '%s\n' '== embed semantic Kanki bridges =='
cp bridge/anki_bridge.rs "$ANKI_BRIDGE_RS"
cp bridge/sync_bridge.rs "$ANKI_SYNC_RS"
mkdir -p "$(dirname "$ANKI_FIXTURE_RS")"
cp bridge/fixture.rs "$ANKI_FIXTURE_RS"
python3 - <<'PY'
from pathlib import Path

lib = Path("third_party/anki/rslib/src/lib.rs")
text = lib.read_text()
needle = "pub mod version;"
assert needle in text
if "pub mod kanki_bridge;" not in text:
    text = text.replace(
        needle,
        needle + "\npub mod kanki_bridge;\npub mod kanki_sync_bridge;",
        1,
    )
lib.write_text(text)

cargo = Path("third_party/anki/rslib/Cargo.toml")
text = cargo.read_text()
if "[lib]" not in text:
    text += '\n[lib]\ncrate-type = ["cdylib", "rlib"]\n'
elif 'crate-type = ["cdylib", "rlib"]' not in text:
    raise SystemExit("kanki-host-anki: existing [lib] section must declare cdylib and rlib")
cargo.write_text(text)
PY

printf '%s\n' '== compile typed Anki host library =='
(
    cd third_party/anki
    cargo build -p anki --release --features rustls --lib --bin kanki_fixture
    cargo build -p anki-sync-server --release
)

LIB=third_party/anki/target/release/libanki.so
test -f "$LIB"
mkdir -p "$SCRATCH/media"

printf '%s\n' '== seed disposable collection with pinned Anki =='
third_party/anki/target/release/kanki_fixture \
    "$SCRATCH/collection.anki2" "$SCRATCH/media" "$SCRATCH/media.db2"
gcc -O2 -Wall -Wextra -Werror bridge/smoke.c -Ibridge \
    -L"$(dirname "$LIB")" -lanki \
    -Wl,-rpath,"$(realpath "$(dirname "$LIB")")" \
    -o "$SCRATCH/kanki-bridge-smoke"

printf '%s\n' '== run disposable collection C ABI smoke =='
"$SCRATCH/kanki-bridge-smoke" \
    "$SCRATCH/collection.anki2" "$SCRATCH/media" "$SCRATCH/media.db2" \
    | tee "$OUT_DIR/bridge-smoke.txt"
for result in build open decks health close sync_open sync_close; do
    grep -q "^${result}={\"ok\":true" "$OUT_DIR/bridge-smoke.txt"
done

printf '%s\n' '== run queue/render/AV/type-answer/answer/bury/reopen integration =='
python3 tests/anki_bridge_integration.py \
    "$LIB" "$SCRATCH/collection.anki2" "$SCRATCH/media" "$SCRATCH/media.db2" \
    | tee "$OUT_DIR/bridge-integration.txt"
grep -q '^anki bridge integration: pass$' "$OUT_DIR/bridge-integration.txt"

printf '%s\n' '== run controlled normal/full/media sync integration =='
SYNC_FIXTURE_USER=kanki-sync-fixture
SYNC_FIXTURE_PASSWORD=kanki-sync-fixture-password
SYNC_SERVER_PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
SYNC_ENDPOINT="http://127.0.0.1:${SYNC_SERVER_PORT}/"
SYNC_SERVER=third_party/anki/target/release/anki-sync-server
mkdir -p "$SCRATCH/sync-server" "$SCRATCH/client-b-media"
SYNC_BASE="$SCRATCH/sync-server" \
SYNC_HOST=127.0.0.1 \
SYNC_PORT="$SYNC_SERVER_PORT" \
SYNC_USER1="$SYNC_FIXTURE_USER:$SYNC_FIXTURE_PASSWORD" \
RUST_LOG=anki=error \
    "$SYNC_SERVER" >"$SCRATCH/sync-server.log" 2>&1 &
SYNC_SERVER_PID=$!
SYNC_SERVER_READY=0
SYNC_SERVER_ATTEMPT=0
while [ "$SYNC_SERVER_ATTEMPT" -lt 100 ]; do
    if SYNC_HOST=127.0.0.1 SYNC_PORT="$SYNC_SERVER_PORT" \
        "$SYNC_SERVER" --healthcheck >/dev/null 2>&1; then
        SYNC_SERVER_READY=1
        break
    fi
    if ! kill -0 "$SYNC_SERVER_PID" 2>/dev/null; then
        break
    fi
    SYNC_SERVER_ATTEMPT=$((SYNC_SERVER_ATTEMPT + 1))
    sleep 0.1
done
if [ "$SYNC_SERVER_READY" != 1 ]; then
    echo 'kanki-host-anki: controlled sync server did not become ready' >&2
    exit 73
fi
KANKI_SYNC_FIXTURE_USER="$SYNC_FIXTURE_USER" \
KANKI_SYNC_FIXTURE_PASSWORD="$SYNC_FIXTURE_PASSWORD" \
python3 tests/sync_bridge_integration.py \
    "$LIB" \
    "$SCRATCH/collection.anki2" "$SCRATCH/media" "$SCRATCH/media.db2" \
    "$SCRATCH/client-b.anki2" "$SCRATCH/client-b-media" "$SCRATCH/client-b-media.db2" \
    "$SYNC_ENDPOINT" \
    | tee "$OUT_DIR/sync-integration.txt"
grep -q '^sync bridge integration: pass$' "$OUT_DIR/sync-integration.txt"
SYNC_FIXTURE_HKEY=$(python3 -c 'import hashlib,sys; print(hashlib.sha1((sys.argv[1] + ":" + sys.argv[2]).encode()).hexdigest())' "$SYNC_FIXTURE_USER" "$SYNC_FIXTURE_PASSWORD")
for SYNC_SECRET in "$SYNC_FIXTURE_USER" "$SYNC_FIXTURE_PASSWORD" "$SYNC_FIXTURE_HKEY"; do
    if grep -Fq -- "$SYNC_SECRET" "$OUT_DIR/sync-integration.txt" "$SCRATCH/sync-server.log"; then
        echo 'kanki-host-anki: sync evidence contains credential material' >&2
        exit 74
    fi
done
kill "$SYNC_SERVER_PID" 2>/dev/null || true
wait "$SYNC_SERVER_PID" 2>/dev/null || true
SYNC_SERVER_PID=

printf '%s\n' '== audit host ABI exports =='
nm -D --defined-only "$LIB" > "$SCRATCH/bridge-all-exports.txt"
: > "$OUT_DIR/bridge-exports.txt"
while IFS= read -r symbol; do
    [ -n "$symbol" ] || continue
    if ! grep -E " [TW] ${symbol}$" "$SCRATCH/bridge-all-exports.txt" \
        >> "$OUT_DIR/bridge-exports.txt"; then
        echo "kanki-host-anki: required ABI export missing: $symbol" >&2
        exit 75
    fi
done < bridge/required_exports.txt
cat "$OUT_DIR/bridge-exports.txt"
readelf -d "$LIB" > "$OUT_DIR/bridge-dynamic.txt"
sha256sum "$LIB" > "$OUT_DIR/bridge-library.sha256"

printf '\nKanki host Anki bridge: PASS\n'
printf 'commit: %s\n' "$BUILD_COMMIT"
printf 'library: %s\n' "$LIB"
cat "$OUT_DIR/bridge-library.sha256"
