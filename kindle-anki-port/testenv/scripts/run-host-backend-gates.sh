#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT to kindle-anki-port source root}
ANKI=${ANKI:?set ANKI to the exact pinned official Anki checkout}
CARGO_HOME=${CARGO_HOME:?set CARGO_HOME to the prepared offline cache}
PROTOC=${PROTOC:?set PROTOC to the pinned protoc executable}
export CARGO_HOME PROTOC CARGO_NET_OFFLINE=true
if [ -z "${PROTOC_LIBDIR:-}" ]; then
  protoc_root=$(dirname "$(dirname "$PROTOC")")
  for candidate in "$protoc_root/runlib" "$protoc_root/minlib" "$protoc_root/lib"; do
    if [ -d "$candidate" ] && [ ! -e "$candidate/libc.so.6" ]; then
      PROTOC_LIBDIR=$candidate
      break
    fi
  done
fi
if [ -n "${PROTOC_LIBDIR:-}" ] && [ -d "$PROTOC_LIBDIR" ]; then
  export LD_LIBRARY_PATH="$PROTOC_LIBDIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
fi

python3 "$PROJECT/tools/inject_into_anki.py" --project "$PROJECT" --anki "$ANKI" --skip-submodules
cd "$ANKI"
cargo check -p anki --features rustls --lib --offline
cargo test -p anki --features rustls --lib --offline --no-fail-fast
cargo build -p anki --features rustls --release --offline
nm -D target/release/libanki.so | grep ' kap_'
