#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the ARMHF gate output directory}
ROOTFS=${ROOTFS:?set ROOTFS to a checksum-verified PW6 rootfs}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:?set TOOLCHAIN_BIN to KindleHF bin directory}
TRIPLE=${TRIPLE:-arm-kindlehf-linux-gnueabihf}
OUT=${OUT:-$PROJECT/build/qemu}

command -v "$QEMU_ARM" >/dev/null 2>&1 || { echo "qemu-arm not found: $QEMU_ARM" >&2; exit 69; }
[ -e "$ROOTFS/lib/ld-linux-armhf.so.3" ] || { echo "rootfs lacks ARMHF loader" >&2; exit 66; }
[ -r "$ARMHF/libanki-kindle.so" ] || { echo "missing ARMHF backend" >&2; exit 66; }

mkdir -p "$OUT"
"$TOOLCHAIN_BIN/$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror \
  -I"$PROJECT/core" "$PROJECT/testenv/qemu/smoke.c" -ldl -o "$OUT/kap-qemu-smoke"

# The backend expects its normal shared-library closure from the target rootfs.
# Keep the production binary unchanged; only QEMU's loader prefix is virtualized.
"$QEMU_ARM" -L "$ROOTFS" "$OUT/kap-qemu-smoke" "$ARMHF/libanki-kindle.so" \
  | tee "$OUT/backend-smoke.txt"
"$QEMU_ARM" -L "$ROOTFS" "$ARMHF/kap-audio" --self-test \
  | tee "$OUT/audio-self-test.txt"
"$QEMU_ARM" -L "$ROOTFS" "$ARMHF/kap-sync" --self-test \
  | tee "$OUT/sync-self-test.txt"
printf 'QEMU smoke: PASS\n' | tee "$OUT/QEMU-SMOKE.txt"
