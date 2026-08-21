#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT to kindle-anki-port source root}
ANKI=${ANKI:?set ANKI to the exact pinned official Anki checkout}
CARGO_HOME=${CARGO_HOME:?set CARGO_HOME to the prepared offline cache}
PROTOC=${PROTOC:?set PROTOC to the pinned protoc executable}
export CARGO_HOME PROTOC CARGO_NET_OFFLINE=true

python3 "$PROJECT/tools/inject_into_anki.py" --project "$PROJECT" --anki "$ANKI" --skip-submodules
cd "$ANKI"
cargo check -p anki --features rustls --lib --offline
cargo test -p anki --features rustls --lib --offline --no-fail-fast
cargo build -p anki --features rustls --release --offline
nm -D target/release/libanki.so | grep ' kap_'
