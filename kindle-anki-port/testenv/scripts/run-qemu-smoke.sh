#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the ARMHF gate output directory}
ROOTFS=${ROOTFS:?set ROOTFS to the checksum-verified PW6 rootfs}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
TOOLCHAIN_BIN=${TOOLCHAIN_BIN:?set TOOLCHAIN_BIN to KindleHF bin directory}
TRIPLE=${TRIPLE:-arm-kindlehf-linux-gnueabihf}
OUT=${OUT:-$PROJECT/build/qemu}
CANONICAL_ROOTFS_MANIFEST=$PROJECT/testenv/qemu/pw6-5.19.6-rootfs-manifest.json
ROOTFS_MANIFEST=${ROOTFS_MANIFEST:-$CANONICAL_ROOTFS_MANIFEST}
BUILD_COMMIT=${BUILD_COMMIT:-$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null || printf unknown)}
ANKI_COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$PROJECT/upstream.lock.json")

# Exact-rootfs QEMU evidence is a release gate, not an interchangeable smoke
# fixture. Bind it to the current clean project source, the pinned Anki base,
# the corresponding ARMHF release outputs, and the canonical PW6 manifest.
if ! printf '%s\n' "$BUILD_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "BUILD_COMMIT must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if ! PROJECT_HEAD=$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null); then
  echo "PROJECT must be a Git checkout for exact-rootfs QEMU smoke" >&2
  exit 66
fi
if [ "$PROJECT_HEAD" != "$BUILD_COMMIT" ]; then
  echo "BUILD_COMMIT does not match project HEAD: $BUILD_COMMIT != $PROJECT_HEAD" >&2
  exit 66
fi
if [ -n "$(git -C "$PROJECT" status --porcelain --untracked-files=all -- .)" ]; then
  echo "project source tree is dirty; refusing exact-rootfs QEMU smoke" >&2
  git -C "$PROJECT" status --short --untracked-files=all -- . >&2 || true
  exit 66
fi
if ! printf '%s\n' "$ANKI_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "upstream.lock.json commit must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
[ -r "$CANONICAL_ROOTFS_MANIFEST" ] || {
  echo "canonical PW6 rootfs manifest is missing: $CANONICAL_ROOTFS_MANIFEST" >&2
  exit 66
}
[ -r "$ROOTFS_MANIFEST" ] || {
  echo "PW6 rootfs manifest is unreadable: $ROOTFS_MANIFEST" >&2
  exit 66
}
if ! cmp -s "$ROOTFS_MANIFEST" "$CANONICAL_ROOTFS_MANIFEST"; then
  echo "ROOTFS_MANIFEST does not match the canonical PW6 5.19.6 manifest" >&2
  exit 66
fi
for required in kap-app kap-audio kap-sync libanki-kindle.so ARMHF-GATES.txt BUILD-PROVENANCE.txt; do
  [ -s "$ARMHF/$required" ] || {
    echo "missing/non-empty ARMHF artifact: $ARMHF/$required" >&2
    exit 66
  }
done
grep -qx 'ARMHF gates: PASS' "$ARMHF/ARMHF-GATES.txt" || {
  echo "ARMHF-GATES.txt does not record PASS" >&2
  exit 66
}
ARMHF_BUILD_COMMIT=$(sed -n 's/^source_commit=//p' "$ARMHF/BUILD-PROVENANCE.txt")
ARMHF_ANKI_COMMIT=$(sed -n 's/^anki_commit=//p' "$ARMHF/BUILD-PROVENANCE.txt")
[ "$ARMHF_BUILD_COMMIT" = "$BUILD_COMMIT" ] || {
  echo "ARMHF source_commit mismatch: $ARMHF_BUILD_COMMIT != $BUILD_COMMIT" >&2
  exit 66
}
[ "$ARMHF_ANKI_COMMIT" = "$ANKI_COMMIT" ] || {
  echo "ARMHF anki_commit mismatch: $ARMHF_ANKI_COMMIT != $ANKI_COMMIT" >&2
  exit 66
}

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

mkdir -p "$OUT"
verify=(python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" "$ROOTFS" --manifest "$ROOTFS_MANIFEST")
if [ -n "${ROOTFS_IMAGE:-}" ]; then
  verify+=(--rootfs-image "$ROOTFS_IMAGE")
fi
"${verify[@]}" | tee "$OUT/rootfs-verification.txt"

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
  printf 'source_commit=%s\n' "$BUILD_COMMIT"
  printf 'anki_commit=%s\n' "$ANKI_COMMIT"
  printf 'rootfs_manifest=%s\n' "$ROOTFS_MANIFEST"
  printf 'rootfs_manifest_sha256=%s\n' "$(sha256sum "$ROOTFS_MANIFEST" | awk '{print $1}')"
  printf 'rootfs=%s\n' "$ROOTFS"
  [ -z "${ROOTFS_IMAGE:-}" ] || {
    printf 'rootfs_image=%s\n' "$ROOTFS_IMAGE"
    printf 'rootfs_image_sha256=%s\n' "$(sha256sum "$ROOTFS_IMAGE" | awk '{print $1}')"
  }
  for binary in libanki-kindle.so kap-app kap-audio kap-sync; do
    printf '%s_sha256=%s\n' "$binary" "$(sha256sum "$ARMHF/$binary" | awk '{print $1}')"
  done
} > "$OUT/QEMU-PROVENANCE.txt"
printf 'QEMU smoke: PASS\n' | tee "$OUT/QEMU-SMOKE.txt"
