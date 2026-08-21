#!/bin/bash
set -euo pipefail

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

TARGET=${TARGET:-armv7-unknown-linux-gnueabihf}
TRIPLE=${TRIPLE:-arm-kindlehf-linux-gnueabihf}
ANKI_COMMIT=${ANKI_COMMIT:-e5a6fbe27fdd4d57d5f712191b4a753032e57853}
KINDLE_SDK_COMMIT=${KINDLE_SDK_COMMIT:-b4a6c99d718a7cf74935f36105c62491b4336a61}
AUDIOBOOK_COMMIT=${AUDIOBOOK_COMMIT:-62edf76feb1b7f4af2f01754957e8d57eb3e7d67}
MINIAUDIO_COMMIT=${MINIAUDIO_COMMIT:-4a5b74bef029b3592c54b6048650ee5f972c1a48}
MATHJAX_VERSION=2.7.9
MATHJAX_SHA256=7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786
ANKI_I18N_NORMALIZATION=btree-map-v1
ANKI_I18N_UPSTREAM_SHA256=0844f9f54d95b1d6008a80226cc75829d1dc638f0388f231272d5ba88d8defb8
ANKI_I18N_NORMALIZED_SHA256=bd0d82698a6a56a095063eee822001a101be55566971493cb4a7552d5600a50c
KOX_VERSION=${KOX_VERSION:-2026.08}
KOX_SHA256=${KOX_SHA256:-8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0}
PROTOC=${PROTOC:-/usr/bin/protoc}
OUT_DIR=${KANKI_OUT_DIR:-$ROOT/out/local-kindle}
SCRATCH=${KANKI_BUILD_SCRATCH:-$ROOT/out/.kindle-build-scratch}
BUILD_COMMIT=${KANKI_BUILD_COMMIT:-$(git rev-parse HEAD)}
BUILD_EPOCH=$(git show -s --format=%ct "$BUILD_COMMIT")
PACKAGE_NAME=${KANKI_PACKAGE_NAME:-Kanki-rewrite-hw3}

case "$BUILD_EPOCH" in
    ''|*[!0-9]*)
        echo "kanki-package: unable to resolve source date epoch for $BUILD_COMMIT" >&2
        exit 70
        ;;
esac

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "kanki-package: required command missing: $1" >&2
        exit 69
    }
}

for command in git cargo rustc curl python3 perl make cmake clang protoc file readelf nm zip unzip zstd sha256sum tar; do
    need "$command"
done

if ! rustc --version | grep -q '^rustc 1\.92\.0 '; then
    echo "kanki-package: rustc 1.92.0 required; found: $(rustc --version)" >&2
    exit 70
fi

if [ "${KANKI_ALLOW_DIRTY:-0}" != "1" ]; then
    if ! git diff --quiet --ignore-submodules=dirty || ! git diff --cached --quiet --ignore-submodules=dirty; then
        echo "kanki-package: repository has uncommitted changes; commit them or set KANKI_ALLOW_DIRTY=1" >&2
        exit 71
    fi
fi

if [ "$(git -C third_party/anki rev-parse HEAD)" != "$ANKI_COMMIT" ]; then
    echo "kanki-package: Anki gitlink does not match $ANKI_COMMIT" >&2
    exit 72
fi
if [ "$(git -C third_party/kindle-sdk rev-parse HEAD)" != "$KINDLE_SDK_COMMIT" ]; then
    echo "kanki-package: Kindle SDK gitlink does not match $KINDLE_SDK_COMMIT" >&2
    exit 72
fi
if [ "$(git -C third_party/audiobook-koplugin rev-parse HEAD)" != "$AUDIOBOOK_COMMIT" ]; then
    echo "kanki-package: audiobook helper gitlink does not match $AUDIOBOOK_COMMIT" >&2
    exit 72
fi

mkdir -p "$OUT_DIR" "$SCRATCH"
rm -rf "$OUT_DIR/package"
rm -f "$OUT_DIR/$PACKAGE_NAME.zip" "$OUT_DIR/$PACKAGE_NAME.zip.sha256" \
      "$OUT_DIR/package-contents.txt" "$OUT_DIR/package-exports.txt" \
      "$OUT_DIR/package-glibc.txt" "$OUT_DIR/sysroot-glibc.txt" \
      "$OUT_DIR/toolchain-info.txt" "$OUT_DIR/mathjax-info.txt" \
      "$OUT_DIR/anki-i18n-info.txt" "$OUT_DIR/archive-info.txt"

ANKI_LIB_RS=third_party/anki/rslib/src/lib.rs
ANKI_CARGO=third_party/anki/rslib/Cargo.toml
ANKI_I18N_GATHER=third_party/anki/rslib/i18n/gather.rs
ANKI_BRIDGE_RS=third_party/anki/rslib/src/kanki_bridge.rs
ANKI_SYNC_RS=third_party/anki/rslib/src/kanki_sync_bridge.rs
LIB_BACKUP="$SCRATCH/anki-lib.rs.original"
CARGO_BACKUP="$SCRATCH/anki-Cargo.toml.original"
I18N_GATHER_BACKUP="$SCRATCH/anki-i18n-gather.rs.original"
cp "$ANKI_LIB_RS" "$LIB_BACKUP"
cp "$ANKI_CARGO" "$CARGO_BACKUP"
cp "$ANKI_I18N_GATHER" "$I18N_GATHER_BACKUP"

cleanup() {
    cp "$LIB_BACKUP" "$ANKI_LIB_RS" 2>/dev/null || true
    cp "$CARGO_BACKUP" "$ANKI_CARGO" 2>/dev/null || true
    cp "$I18N_GATHER_BACKUP" "$ANKI_I18N_GATHER" 2>/dev/null || true
    rm -f "$ANKI_BRIDGE_RS" "$ANKI_SYNC_RS"
}
trap cleanup EXIT INT TERM

printf '%s\n' '== initialize pinned Anki translation submodules =='
git -C third_party/anki submodule update --init --depth 1 ftl/core-repo ftl/qt-repo
mkdir -p third_party/anki/out/rslib/proto third_party/anki/out/extracted/protoc/bin
ln -sf "$PROTOC" third_party/anki/out/extracted/protoc/bin/protoc

printf '%s\n' '== normalize pinned Anki i18n build order =='
python3 tools/normalize_anki_i18n.py "$ANKI_I18N_GATHER" \
    | tee "$OUT_DIR/anki-i18n-info.txt"
grep -q "KANKI_ANKI_I18N_NORMALIZATION=$ANKI_I18N_NORMALIZATION" \
    "$OUT_DIR/anki-i18n-info.txt"
grep -q "KANKI_ANKI_I18N_UPSTREAM_SHA256=$ANKI_I18N_UPSTREAM_SHA256" \
    "$OUT_DIR/anki-i18n-info.txt"
grep -q "KANKI_ANKI_I18N_NORMALIZED_SHA256=$ANKI_I18N_NORMALIZED_SHA256" \
    "$OUT_DIR/anki-i18n-info.txt"

printf '%s\n' '== install/reuse pinned KindleHF toolchain =='
KOX_MARKER="$HOME/.kanki-kox-${KOX_VERSION}-${KOX_SHA256}"
TC="$HOME/x-tools/$TRIPLE"
if [ -x "$TC/bin/$TRIPLE-gcc" ] && [ -f "$KOX_MARKER" ]; then
    {
        printf 'KANKI_KOX_VERSION=%s\n' "$KOX_VERSION"
        printf 'KANKI_KOX_SHA256=%s\n' "$KOX_SHA256"
        printf 'KANKI_KOX_ROOT=%s\n' "$TC"
    } | tee "$OUT_DIR/toolchain-info.txt"
else
    bash tools/install_kindlehf_toolchain.sh "$HOME" | tee "$OUT_DIR/toolchain-info.txt"
    grep -q "KANKI_KOX_VERSION=$KOX_VERSION" "$OUT_DIR/toolchain-info.txt"
    grep -q "KANKI_KOX_SHA256=$KOX_SHA256" "$OUT_DIR/toolchain-info.txt"
    : > "$KOX_MARKER"
fi

KHF_SYSROOT="$TC/$TRIPLE/sysroot"
export PATH="$TC/bin:$PATH"
export CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER="$TC/bin/$TRIPLE-gcc"
export CC_armv7_unknown_linux_gnueabihf="$TC/bin/$TRIPLE-gcc"
export CXX_armv7_unknown_linux_gnueabihf="$TC/bin/$TRIPLE-g++"
export AR_armv7_unknown_linux_gnueabihf="$TC/bin/$TRIPLE-ar"
export CFLAGS_armv7_unknown_linux_gnueabihf='-march=armv7-a -mtune=cortex-a7 -mfpu=neon -mfloat-abi=hard -fno-stack-protector -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0'
export CXXFLAGS_armv7_unknown_linux_gnueabihf="$CFLAGS_armv7_unknown_linux_gnueabihf"
export RUSTFLAGS='-C target-cpu=cortex-a7 -C link-arg=-Wl,--as-needed'
export PROTOC

if command -v rustup >/dev/null 2>&1; then
    rustup target add "$TARGET" >/dev/null
fi

printf '%s\n' '== fetch pinned miniaudio =='
MINIAUDIO_H="$SCRATCH/miniaudio.h"
curl -fL --retry 3 "https://raw.githubusercontent.com/mackron/miniaudio/$MINIAUDIO_COMMIT/miniaudio.h" -o "$MINIAUDIO_H"

printf '%s\n' '== install pinned MathJax renderer =='
MATHJAX_SOURCE="$ROOT/out/kindle-package-vendor/mathjax-$MATHJAX_VERSION"
sh tools/install_mathjax.sh "$MATHJAX_SOURCE" | tee "$OUT_DIR/mathjax-info.txt"
grep -q "KANKI_MATHJAX_VERSION=$MATHJAX_VERSION" "$OUT_DIR/mathjax-info.txt"
grep -q "KANKI_MATHJAX_SHA256=$MATHJAX_SHA256" "$OUT_DIR/mathjax-info.txt"

printf '%s\n' '== embed semantic Kanki bridges in pinned Anki =='
cp bridge/anki_bridge.rs "$ANKI_BRIDGE_RS"
cp bridge/sync_bridge.rs "$ANKI_SYNC_RS"
python3 - <<'PY'
from pathlib import Path
lib = Path('third_party/anki/rslib/src/lib.rs')
text = lib.read_text()
needle = 'pub mod version;'
assert needle in text
if 'pub mod kanki_bridge;' not in text:
    text = text.replace(needle, needle + '\npub mod kanki_bridge;\npub mod kanki_sync_bridge;', 1)
lib.write_text(text)

cargo = Path('third_party/anki/rslib/Cargo.toml')
text = cargo.read_text()
if '[lib]' not in text:
    text += '\n[lib]\ncrate-type = ["cdylib"]\n'
elif 'crate-type = ["cdylib"]' not in text:
    raise SystemExit('kanki-package: existing [lib] section must declare cdylib explicitly')
cargo.write_text(text)
PY

printf '%s\n' '== build typed Anki backend =='
(
    cd third_party/anki
    cargo build -p anki --release --target "$TARGET" --features rustls
)

printf '%s\n' '== build Kindle native executables =='
"$TRIPLE-gcc" -std=c11 -Os -fsigned-char -Wall -Wextra -Werror -Ibridge \
    -DKANKI_BUILD_COMMIT=\"$BUILD_COMMIT\" -DKANKI_ANKI_COMMIT=\"$ANKI_COMMIT\" \
    device/kanki_device.c -ldl -o "$SCRATCH/kanki-device"
"$TRIPLE-gcc" -std=c11 -Os -fsigned-char -Wall -Wextra -Werror -Ibridge \
    device/kanki_sync_cli.c -ldl -o "$SCRATCH/kanki-sync"
"$TRIPLE-gcc" -std=c11 -D_POSIX_C_SOURCE=200809L -Os -fsigned-char -Wall -Wextra -Werror \
    device/kanki_diag_server.c -o "$SCRATCH/kanki-diag"
"$TRIPLE-gcc" -std=c11 -Os -fsigned-char -Wall -Wextra -Werror \
    -ffreestanding -fno-builtin -fno-stack-protector -nostdlib \
    -Wl,-e,_start -Wl,--dynamic-linker=/lib/ld-linux-armhf.so.3 \
    device/kanki_raise.c -ldl -o "$SCRATCH/kanki-raise"
"$TRIPLE-gcc" -std=c11 -D_XOPEN_SOURCE=700 -O2 -Wall -Wextra -Werror \
    -I"$SCRATCH" device/audio/kanki_audio_server.c -o "$SCRATCH/kanki-audio" -lm -latomic
"$TRIPLE-gcc" -std=gnu11 -D_GNU_SOURCE -D_POSIX_C_SOURCE=200809L \
    -O2 -Wall -Wextra -Werror -DKGP_NATIVE_GLIBC \
    third_party/audiobook-koplugin/kindle/gst-play.c -o "$SCRATCH/kanki-gst-play" -ldl
file "$SCRATCH"/kanki-device "$SCRATCH"/kanki-sync "$SCRATCH"/kanki-diag \
     "$SCRATCH"/kanki-raise "$SCRATCH"/kanki-audio "$SCRATCH"/kanki-gst-play
if "$TRIPLE-nm" -D "$SCRATCH/kanki-raise" \
    | grep -E ' U (malloc|free|memcpy|memset|fprintf|getenv|setenv|write)$'; then
    echo "kanki-package: freestanding reactivation helper imports forbidden libc symbols" >&2
    exit 1
fi

printf '%s\n' '== assemble self-identifying package =='
ROOT_PACKAGE="$OUT_DIR/package"
EXT="$ROOT_PACKAGE/extensions/kanki"
MATHJAX_DEST="$EXT/assets/vendor/mathjax-$MATHJAX_VERSION"
mkdir -p "$EXT/assets/device" "$EXT/assets/reviewer" "$MATHJAX_DEST" \
         "$ROOT_PACKAGE/documents"
cp "third_party/anki/target/$TARGET/release/libanki.so" "$EXT/libanki-kanki.so"
cp "$SCRATCH"/kanki-device "$SCRATCH"/kanki-sync "$SCRATCH"/kanki-diag \
   "$SCRATCH"/kanki-raise "$SCRATCH"/kanki-audio "$SCRATCH"/kanki-gst-play "$EXT/"
cp assets/device/* "$EXT/assets/device/"
cp assets/reviewer/reviewer.css assets/reviewer/reviewer.js \
   assets/reviewer/css_compat.js assets/reviewer/css_runtime.js \
   assets/reviewer/mathjax_runtime.js assets/reviewer/diagnostics.js \
   "$EXT/assets/reviewer/"
cp -R "$MATHJAX_SOURCE/." "$MATHJAX_DEST/"
cp scripts/kanki-launch.sh scripts/kanki-sync.sh scripts/kanki-report.sh \
   scripts/kanki-operation-lock.sh scripts/kanki-verify.sh "$EXT/"
cp packaging/config.example.ini "$EXT/"
cp packaging/kanki.operation.lock "$EXT/.kanki.operation.lock"
cp THIRD_PARTY_NOTICES.md docs/INSTALL.md "$EXT/"
cp packaging/documents/* "$ROOT_PACKAGE/documents/"
cat > "$EXT/BUILD.json" <<EOF
{
  "version": "0.1.0-hw3",
  "kanki_commit": "$BUILD_COMMIT",
  "anki_commit": "$ANKI_COMMIT",
  "kindle_sdk_commit": "$KINDLE_SDK_COMMIT",
  "audiobook_commit": "$AUDIOBOOK_COMMIT",
  "miniaudio_commit": "$MINIAUDIO_COMMIT",
  "mathjax_version": "$MATHJAX_VERSION",
  "mathjax_sha256": "$MATHJAX_SHA256",
  "anki_i18n_normalization": "$ANKI_I18N_NORMALIZATION",
  "anki_i18n_upstream_sha256": "$ANKI_I18N_UPSTREAM_SHA256",
  "anki_i18n_normalized_sha256": "$ANKI_I18N_NORMALIZED_SHA256",
  "source_date_epoch": $BUILD_EPOCH,
  "koxtoolchain_version": "$KOX_VERSION",
  "koxtoolchain_sha256": "$KOX_SHA256",
  "target": "$TARGET",
  "reviewer_protocol": 1,
  "diagnostics_protocol": 1,
  "builder": "tools/build_kindle_package.sh",
  "release_gate": "PW6 hardware acceptance required"
}
EOF
find "$ROOT_PACKAGE" -type d -exec chmod 755 {} +
find "$ROOT_PACKAGE" -type f -exec chmod 644 {} +
chmod 755 "$EXT/kanki-device" "$EXT/kanki-sync" "$EXT/kanki-diag" "$EXT/kanki-raise" \
          "$EXT/kanki-audio" "$EXT/kanki-gst-play" "$EXT/kanki-launch.sh" \
          "$EXT/kanki-sync.sh" "$EXT/kanki-report.sh" \
          "$EXT/kanki-operation-lock.sh" "$EXT/kanki-verify.sh" \
          "$ROOT_PACKAGE/documents/"*.sh
(cd "$EXT" && find . -type f ! -name MANIFEST.sha256 ! -name config.ini ! -name kanki.log -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256)
python3 tools/create_reproducible_zip.py \
    "$ROOT_PACKAGE" "$OUT_DIR/$PACKAGE_NAME.zip" "$BUILD_EPOCH" \
    | tee "$OUT_DIR/archive-info.txt"
sha256sum "$OUT_DIR/$PACKAGE_NAME.zip" > "$OUT_DIR/$PACKAGE_NAME.zip.sha256"

printf '%s\n' '== package and ABI gates =='
test -x "$EXT/kanki-raise"
test -x "$EXT/kanki-diag"
test -x "$EXT/kanki-report.sh"
test -x "$EXT/kanki-operation-lock.sh"
test -x "$EXT/kanki-verify.sh"
test -f "$EXT/.kanki.operation.lock"
test -f "$EXT/assets/reviewer/css_compat.js"
test -f "$EXT/assets/reviewer/css_runtime.js"
test -f "$EXT/assets/reviewer/mathjax_runtime.js"
test -f "$EXT/assets/reviewer/diagnostics.js"
test -f "$MATHJAX_DEST/MathJax.js"
test -f "$MATHJAX_DEST/config/TeX-AMS_SVG-full.js"
test -f "$MATHJAX_DEST/jax/output/SVG/jax.js"
test -f "$MATHJAX_DEST/LICENSE"
test -f "$EXT/assets/device/sync.html"
grep -q 'css_compat.js' "$EXT/assets/device/reviewer-shell.html"
grep -q 'css_runtime.js' "$EXT/assets/device/reviewer-shell.html"
grep -q 'MathJax.js?config=TeX-AMS_SVG-full' "$EXT/assets/device/reviewer-shell.html"
grep -q 'mathjax_runtime.js' "$EXT/assets/device/reviewer-shell.html"
grep -q 'diagnostics.js' "$EXT/assets/device/reviewer-shell.html"
grep -q 'kanki://sync/run?mode=normal' "$EXT/assets/device/sync.html"
grep -q 'kanki://sync/run?mode=upload' "$EXT/assets/device/sync.html"
grep -q 'kanki://sync/run?mode=download' "$EXT/assets/device/sync.html"
grep -q 'DISPLAY="${DISPLAY:-:0}"' "$EXT/kanki-launch.sh"
grep -q 'render-debug' "$EXT/kanki-launch.sh"
grep -q 'kanki-verify.sh' "$EXT/kanki-launch.sh"
grep -q 'kanki_operation_lock_acquire launch' "$EXT/kanki-launch.sh"
grep -q 'kanki_operation_lock_acquire sync' "$EXT/kanki-sync.sh"
grep -q '/usr/bin/flock' "$EXT/kanki-operation-lock.sh"
grep -q 'unexpected file outside package manifest' "$EXT/kanki-verify.sh"
grep -q 'enable-render-capture' "$EXT/kanki-diag"
grep -q "\"koxtoolchain_version\": \"$KOX_VERSION\"" "$EXT/BUILD.json"
grep -q "\"koxtoolchain_sha256\": \"$KOX_SHA256\"" "$EXT/BUILD.json"
grep -q "\"mathjax_version\": \"$MATHJAX_VERSION\"" "$EXT/BUILD.json"
grep -q "\"mathjax_sha256\": \"$MATHJAX_SHA256\"" "$EXT/BUILD.json"
grep -q "\"anki_i18n_normalization\": \"$ANKI_I18N_NORMALIZATION\"" \
    "$EXT/BUILD.json"
grep -q "\"anki_i18n_upstream_sha256\": \"$ANKI_I18N_UPSTREAM_SHA256\"" \
    "$EXT/BUILD.json"
grep -q "\"anki_i18n_normalized_sha256\": \"$ANKI_I18N_NORMALIZED_SHA256\"" \
    "$EXT/BUILD.json"
grep -q "\"source_date_epoch\": $BUILD_EPOCH" "$EXT/BUILD.json"
grep -q "KANKI_ARCHIVE_SOURCE_DATE_EPOCH=$BUILD_EPOCH" "$OUT_DIR/archive-info.txt"
python3 tools/check_policy.py
(cd "$EXT" && sha256sum -c MANIFEST.sha256)
unzip -tq "$OUT_DIR/$PACKAGE_NAME.zip"
unzip -l "$OUT_DIR/$PACKAGE_NAME.zip" | tee "$OUT_DIR/package-contents.txt"
if unzip -l "$OUT_DIR/$PACKAGE_NAME.zip" \
    | grep -E 'extensions/ranki|LD_PRELOAD|collection\.anki2|config\.ini$'; then
    echo "kanki-package: archive contains a forbidden legacy/runtime data path" >&2
    exit 1
fi
nm -D --defined-only "$EXT/libanki-kanki.so" > "$SCRATCH/backend-all-exports.txt"
: > "$OUT_DIR/package-exports.txt"
while IFS= read -r symbol; do
    [ -n "$symbol" ] || continue
    if ! grep -E " [TW] ${symbol}$" "$SCRATCH/backend-all-exports.txt" \
        >> "$OUT_DIR/package-exports.txt"; then
        echo "kanki-package: required ABI export missing: $symbol" >&2
        exit 1
    fi
done < bridge/required_exports.txt
cat "$OUT_DIR/package-exports.txt"
for file in "$EXT/libanki-kanki.so" "$EXT/kanki-device" "$EXT/kanki-sync" "$EXT/kanki-diag" "$EXT/kanki-raise" "$EXT/kanki-audio" "$EXT/kanki-gst-play"; do
    readelf --version-info "$file" | grep -oE 'GLIBC_[0-9.]+' || true
done | sort -Vu | tee "$OUT_DIR/package-glibc.txt"
LIBC=$(find "$KHF_SYSROOT" -name libc.so.6 | head -1)
readelf --version-info "$LIBC" | grep -oE 'GLIBC_[0-9.]+' | sort -Vu > "$OUT_DIR/sysroot-glibc.txt"
python3 - "$OUT_DIR/package-glibc.txt" "$OUT_DIR/sysroot-glibc.txt" <<'PY'
from pathlib import Path
import sys

def versions(path):
    return [tuple(map(int, line.split('_', 1)[1].split('.'))) for line in Path(path).read_text().splitlines() if line]

required = versions(sys.argv[1])
available = versions(sys.argv[2])
if required and available and max(required) > max(available):
    raise SystemExit(f'package requires {max(required)}, sysroot provides {max(available)}')
PY

printf '\nKanki package build: PASS\n'
printf 'commit: %s\n' "$BUILD_COMMIT"
printf 'zip: %s\n' "$OUT_DIR/$PACKAGE_NAME.zip"
printf 'sha256: '
sha256sum "$OUT_DIR/$PACKAGE_NAME.zip" | awk '{print $1}'
