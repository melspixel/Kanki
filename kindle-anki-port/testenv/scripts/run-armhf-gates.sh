#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ANKI=${ANKI:?set ANKI}
CARGO_HOME=${CARGO_HOME:?set CARGO_HOME}
PROTOC=${PROTOC:?set PROTOC}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:?set TOOLCHAIN_BIN to KindleHF bin directory}
RUST_TARGET=${KAP_RUST_TARGET:-armv7-unknown-linux-gnueabihf}
OUT=${OUT:-$PROJECT/build/armhf}
TRIPLE=${KAP_TOOLCHAIN_TRIPLE:-arm-kindlehf-linux-gnueabihf}
BUILD_COMMIT=${BUILD_COMMIT:-$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null || printf unknown)}
PINNED_ANKI_COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$PROJECT/upstream.lock.json")
ANKI_COMMIT=${ANKI_COMMIT:-$PINNED_ANKI_COMMIT}

# Bind ARMHF outputs to the exact canonical source identities before any build
# command runs.  Otherwise a dirty project tree can be compiled, later cleaned,
# and then packaged under the unchanged HEAD; likewise a checkout of a different
# Anki revision could previously be stamped with the pinned lock-file commit.
if ! printf '%s\n' "$BUILD_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "BUILD_COMMIT must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if ! PROJECT_HEAD=$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null); then
  echo "PROJECT must be a Git checkout for an ARMHF release build" >&2
  exit 66
fi
if [ "$PROJECT_HEAD" != "$BUILD_COMMIT" ]; then
  echo "BUILD_COMMIT does not match project HEAD: $BUILD_COMMIT != $PROJECT_HEAD" >&2
  exit 66
fi
if [ -n "$(git -C "$PROJECT" status --porcelain --untracked-files=all -- .)" ]; then
  echo "project source tree is dirty; refusing ARMHF release build" >&2
  git -C "$PROJECT" status --short --untracked-files=all -- . >&2 || true
  exit 66
fi
if ! printf '%s\n' "$PINNED_ANKI_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "upstream.lock.json commit must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if [ "$ANKI_COMMIT" != "$PINNED_ANKI_COMMIT" ]; then
  echo "ANKI_COMMIT does not match upstream.lock.json: $ANKI_COMMIT != $PINNED_ANKI_COMMIT" >&2
  exit 67
fi
if ! ANKI_HEAD=$(git -C "$ANKI" rev-parse HEAD 2>/dev/null); then
  echo "ANKI must be a Git checkout for an ARMHF release build" >&2
  exit 67
fi
if [ "$ANKI_HEAD" != "$PINNED_ANKI_COMMIT" ]; then
  echo "Anki checkout HEAD does not match upstream.lock.json: $ANKI_HEAD != $PINNED_ANKI_COMMIT" >&2
  exit 67
fi

export PATH="$TOOLCHAIN_BIN:$PATH"
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
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="$TRIPLE-gcc"
export CC_armv7_unknown_linux_gnueabihf="$TRIPLE-gcc"
export CXX_armv7_unknown_linux_gnueabihf="$TRIPLE-g++"
export AR_armv7_unknown_linux_gnueabihf="$TRIPLE-ar"

# The compatibility ceiling must come from the target sysroot, not from the
# build host.  A stale hard-coded ceiling can silently accept a binary that
# links on the cross toolchain but will not load on the Kindle userspace.
SYSROOT=${SYSROOT:-$("$TRIPLE-gcc" --print-sysroot)}
if [ -z "${GLIBC_CEILING:-}" ]; then
  libc="$SYSROOT/lib/libc.so.6"
  [ -r "$libc" ] || libc="$SYSROOT/lib/arm-linux-gnueabihf/libc.so.6"
  [ -r "$libc" ] || { echo "unable to locate target libc in sysroot: $SYSROOT" >&2; exit 94; }
  GLIBC_CEILING=$(
    strings "$libc" | grep -oE 'GLIBC_[0-9]+\.[0-9]+' | sed 's/GLIBC_//' | sort -Vu | tail -1
  )
  [ -n "$GLIBC_CEILING" ] || { echo "unable to derive GLIBC ceiling from $libc" >&2; exit 94; }
fi

rm -rf "$OUT"
mkdir -p "$OUT"
cd "$ANKI"
cargo build -p anki --features rustls --release --target "$RUST_TARGET" --offline
cp "target/$RUST_TARGET/release/libanki.so" "$OUT/libanki-kindle.so"
"$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror -I"$PROJECT/core" \
  -DKAP_BUILD_COMMIT=\"$BUILD_COMMIT\" \
  -DKAP_ANKI_COMMIT=\"$ANKI_COMMIT\" \
  "$PROJECT/native/app.c" -ldl -o "$OUT/kap-app"
"$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror \
  "$PROJECT/native/audio.c" -ldl -o "$OUT/kap-audio"
"$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror -I"$PROJECT/core" \
  "$PROJECT/native/sync.c" -ldl -o "$OUT/kap-sync"

file "$OUT"/* | tee "$OUT/file.txt"
"$TRIPLE-nm" -D "$OUT/libanki-kindle.so" | grep ' kap_' | tee "$OUT/exports.txt"
for symbol in \
  kap_open_collection_json kap_deck_tree_json kap_next_question_json \
  kap_reveal_answer_json kap_answer_json kap_bury_current_json \
  kap_sync_collection_json kap_full_sync_json kap_media_sync_status_json \
  kap_abort_sync_json kap_close_collection_json; do
  grep -q " $symbol$" "$OUT/exports.txt" || { echo "missing export: $symbol" >&2; exit 91; }
done

for binary in libanki-kindle.so kap-app kap-audio kap-sync; do
  "$TRIPLE-readelf" -h -A -d -V "$OUT/$binary" > "$OUT/$binary.abi.txt"
  grep -q 'Machine:.*ARM' "$OUT/$binary.abi.txt" || { echo "$binary is not ARM" >&2; exit 92; }
  grep -q 'Tag_ABI_VFP_args: VFP registers' "$OUT/$binary.abi.txt" || {
    echo "$binary is not hard-float" >&2; exit 93;
  }
  grep -oE 'GLIBC_[0-9.]+' "$OUT/$binary.abi.txt" | sort -Vu > "$OUT/$binary.glibc.txt" || true
  max=$(sed 's/GLIBC_//' "$OUT/$binary.glibc.txt" | tail -1)
  [ -n "$max" ] || max=0
  python3 - "$binary" "$max" "$GLIBC_CEILING" <<'PY'
import sys
def ver(value): return tuple(int(x) for x in value.split('.'))
name, required, ceiling = sys.argv[1:]
print(f"{name}: required GLIBC_{required}; ceiling GLIBC_{ceiling}")
if ver(required) > ver(ceiling):
    raise SystemExit(f"{name} exceeds GLIBC ceiling")
PY
done
{
  printf 'product=Kindle Anki Port\n'
  printf 'source_commit=%s\n' "$BUILD_COMMIT"
  printf 'anki_commit=%s\n' "$ANKI_COMMIT"
  printf 'rust_target=%s\n' "$RUST_TARGET"
  printf 'toolchain_triple=%s\n' "$TRIPLE"
  printf 'sysroot=%s\n' "$SYSROOT"
  printf 'glibc_ceiling=%s\n' "$GLIBC_CEILING"
  "$TRIPLE-gcc" --version | head -1 | sed 's/^/compiler=/'
  cargo --version | sed 's/^/cargo=/'
  rustc --version | sed 's/^/rustc=/'
} > "$OUT/BUILD-PROVENANCE.txt"
printf 'ARMHF gates: PASS\n' | tee "$OUT/ARMHF-GATES.txt"
