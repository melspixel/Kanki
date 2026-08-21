#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
QEMU_ARM=${QEMU_ARM:-qemu-arm-static}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:?set TOOLCHAIN_BIN to KindleHF bin directory}
TRIPLE=${TRIPLE:-arm-kindlehf-linux-gnueabihf}
OUT=${OUT:-$PROJECT/build/qemu-host-sanity}

command -v "$QEMU_ARM" >/dev/null 2>&1 || {
  echo "qemu user-mode binary not found: $QEMU_ARM" >&2
  exit 69
}
[ -x "$TOOLCHAIN_BIN/$TRIPLE-gcc" ] || {
  echo "KindleHF compiler not found: $TOOLCHAIN_BIN/$TRIPLE-gcc" >&2
  exit 66
}

mkdir -p "$OUT"
cat >"$OUT/hello.c" <<'EOF'
#include <stdio.h>
int main(void) {
    puts("kap qemu armhf static sanity: ok");
    return 0;
}
EOF

"$TOOLCHAIN_BIN/$TRIPLE-gcc" -O2 -static -std=c99 -Wall -Wextra -Werror \
  "$OUT/hello.c" -o "$OUT/hello-armhf-static"
file "$OUT/hello-armhf-static" | tee "$OUT/file.txt"
"$TOOLCHAIN_BIN/$TRIPLE-readelf" -h -A "$OUT/hello-armhf-static" \
  >"$OUT/readelf.txt"
grep -q 'Machine:.*ARM' "$OUT/readelf.txt"
grep -q 'Tag_ABI_VFP_args: VFP registers' "$OUT/readelf.txt"
"$QEMU_ARM" --version | head -1 | tee "$OUT/qemu-version.txt"
"$QEMU_ARM" "$OUT/hello-armhf-static" | tee "$OUT/run.txt"
grep -q '^kap qemu armhf static sanity: ok$' "$OUT/run.txt"
printf 'QEMU host sanity: PASS\n' | tee "$OUT/QEMU-HOST-SANITY.txt"
