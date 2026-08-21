#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the ARMHF gate output directory}
ROOTFS=${ROOTFS:?set ROOTFS to the checksum-verified PW6 rootfs}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:?set TOOLCHAIN_BIN to KindleHF bin directory}
TRIPLE=${TRIPLE:-arm-kindlehf-linux-gnueabihf}
OUT=${OUT:-$PROJECT/build/qemu}
ROOTFS_MANIFEST=${ROOTFS_MANIFEST:-$PROJECT/testenv/qemu/pw6-5.19.6-rootfs-manifest.json}

if ! command -v "$QEMU_ARM" >/dev/null 2>&1; then
  if command -v qemu-arm-static >/dev/null 2>&1; then
    QEMU_ARM=qemu-arm-static
  else
    echo "qemu user-mode binary not found: $QEMU_ARM or qemu-arm-static" >&2
    exit 69
  fi
fi
[ -e "$ROOTFS/lib/ld-linux-armhf.so.3" ] || { echo "rootfs lacks ARMHF loader" >&2; exit 66; }
[ -r "$ARMHF/libanki-kindle.so" ] || { echo "missing ARMHF backend" >&2; exit 66; }

verify=(python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" "$ROOTFS" --manifest "$ROOTFS_MANIFEST")
if [ -n "${ROOTFS_IMAGE:-}" ]; then
  verify+=(--rootfs-image "$ROOTFS_IMAGE")
fi
"${verify[@]}"

mkdir -p "$OUT"
"$TOOLCHAIN_BIN/$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror \
  -I"$PROJECT/core" "$PROJECT/testenv/qemu/smoke.c" -ldl -o "$OUT/kap-qemu-smoke"

# The backend expects its normal shared-library closure from the target rootfs.
# Keep production binaries unchanged; only QEMU's loader prefix is virtualized.
"$QEMU_ARM" -L "$ROOTFS" "$OUT/kap-qemu-smoke" "$ARMHF/libanki-kindle.so" \
  | tee "$OUT/backend-smoke.txt"
"$QEMU_ARM" -L "$ROOTFS" "$ARMHF/kap-audio" --self-test \
  | tee "$OUT/audio-self-test.txt"
"$QEMU_ARM" -L "$ROOTFS" "$ARMHF/kap-sync" --self-test \
  | tee "$OUT/sync-self-test.txt"
{
  "$QEMU_ARM" --version | head -1
  printf 'rootfs_manifest=%s\n' "$ROOTFS_MANIFEST"
  printf 'rootfs=%s\n' "$ROOTFS"
  [ -z "${ROOTFS_IMAGE:-}" ] || printf 'rootfs_image=%s\n' "$ROOTFS_IMAGE"
} > "$OUT/QEMU-PROVENANCE.txt"
printf 'QEMU smoke: PASS\n' | tee "$OUT/QEMU-SMOKE.txt"
