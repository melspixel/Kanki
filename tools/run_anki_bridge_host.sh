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
ANKI_LIB_RS=third_party/anki/rslib/src/lib.rs
ANKI_CARGO=third_party/anki/rslib/Cargo.toml
ANKI_BRIDGE_RS=third_party/anki/rslib/src/kanki_bridge.rs
ANKI_SYNC_RS=third_party/anki/rslib/src/kanki_sync_bridge.rs
cp "$ANKI_LIB_RS" "$SCRATCH/lib.rs.original"
cp "$ANKI_CARGO" "$SCRATCH/Cargo.toml.original"

cleanup() {
    cp "$SCRATCH/lib.rs.original" "$ANKI_LIB_RS" 2>/dev/null || true
    cp "$SCRATCH/Cargo.toml.original" "$ANKI_CARGO" 2>/dev/null || true
    rm -f "$ANKI_BRIDGE_RS" "$ANKI_SYNC_RS"
    rm -rf "$SCRATCH"
}
trap cleanup EXIT INT TERM

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/bridge-smoke.txt" "$OUT_DIR/bridge-exports.txt" \
      "$OUT_DIR/bridge-dynamic.txt" "$OUT_DIR/bridge-library.sha256"

printf '%s\n' '== initialize pinned Anki translations =='
git -C third_party/anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
mkdir -p third_party/anki/out/rslib/proto third_party/anki/out/extracted/protoc/bin
ln -sf "$PROTOC" third_party/anki/out/extracted/protoc/bin/protoc

printf '%s\n' '== embed semantic Kanki bridges =='
cp bridge/anki_bridge.rs "$ANKI_BRIDGE_RS"
cp bridge/sync_bridge.rs "$ANKI_SYNC_RS"
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
    text += '\n[lib]\ncrate-type = ["cdylib"]\n'
elif 'crate-type = ["cdylib"]' not in text:
    raise SystemExit("kanki-host-anki: existing [lib] section must declare cdylib")
cargo.write_text(text)
PY

printf '%s\n' '== compile typed Anki host library =='
(
    cd third_party/anki
    cargo build -p anki --release --features rustls
)

LIB=third_party/anki/target/release/libanki.so
test -f "$LIB"
mkdir -p "$SCRATCH/media"
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

printf '%s\n' '== audit host ABI exports =='
nm -D "$LIB" \
    | grep -E ' kanki_(build_info_json|string_free|core_new|open_collection_json|deck_tree_json|health_json|next_card_json|prepare_answer_json|answer_json|bury_current_json|sync_core_new|sync_collection_json|sync_full_json|sync_media_json)$' \
    | tee "$OUT_DIR/bridge-exports.txt"
for symbol in kanki_string_free kanki_health_json kanki_prepare_answer_json; do
    grep -q " ${symbol}$" "$OUT_DIR/bridge-exports.txt"
done
readelf -d "$LIB" > "$OUT_DIR/bridge-dynamic.txt"
sha256sum "$LIB" > "$OUT_DIR/bridge-library.sha256"

printf '\nKanki host Anki bridge: PASS\n'
printf 'commit: %s\n' "$BUILD_COMMIT"
printf 'library: %s\n' "$LIB"
cat "$OUT_DIR/bridge-library.sha256"
