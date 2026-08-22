#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT to kindle-anki-port source root}
ANKI=${ANKI:?set ANKI to the exact pinned official Anki checkout}
CARGO_HOME=${CARGO_HOME:?set CARGO_HOME to the prepared offline cache}
PROTOC=${PROTOC:?set PROTOC to the pinned protoc executable}
BUILD_COMMIT=${BUILD_COMMIT:-$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null || printf unknown)}
PINNED_ANKI_COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$PROJECT/upstream.lock.json")

# Host semantic evidence must be bound to resolvable Git commit objects, not
# merely printable ref values. Git can resolve a ref name even when its object
# is missing; additionally, a failed `git status` inside command substitution
# must not be mistaken for an empty/clean status result.
if ! printf '%s\n' "$BUILD_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "BUILD_COMMIT must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if ! PROJECT_HEAD=$(git -C "$PROJECT" rev-parse --verify 'HEAD^{commit}' 2>/dev/null); then
  echo "PROJECT must have a resolvable Git HEAD commit for a host backend release gate" >&2
  exit 66
fi
if [ "$PROJECT_HEAD" != "$BUILD_COMMIT" ]; then
  echo "BUILD_COMMIT does not match project HEAD: $BUILD_COMMIT != $PROJECT_HEAD" >&2
  exit 66
fi
if ! PROJECT_STATUS=$(git -C "$PROJECT" status --porcelain --untracked-files=all -- . 2>/dev/null); then
  echo "unable to verify project source-tree cleanliness; refusing host backend release gate" >&2
  exit 66
fi
if [ -n "$PROJECT_STATUS" ]; then
  echo "project source tree is dirty; refusing host backend release gate" >&2
  printf '%s\n' "$PROJECT_STATUS" >&2
  exit 66
fi
if ! printf '%s\n' "$PINNED_ANKI_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "upstream.lock.json commit must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if ! ANKI_HEAD=$(git -C "$ANKI" rev-parse --verify 'HEAD^{commit}' 2>/dev/null); then
  echo "ANKI must have a resolvable Git HEAD commit for a host backend release gate" >&2
  exit 67
fi
if [ "$ANKI_HEAD" != "$PINNED_ANKI_COMMIT" ]; then
  echo "Anki checkout HEAD does not match upstream.lock.json: $ANKI_HEAD != $PINNED_ANKI_COMMIT" >&2
  exit 67
fi

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
