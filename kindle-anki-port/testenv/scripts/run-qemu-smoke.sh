#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the ARMHF gate output directory}
ROOTFS=${ROOTFS:?set ROOTFS to the checksum-verified PW6 rootfs}
ROOTFS_IMAGE=${ROOTFS_IMAGE:-}
QEMU_ARM=${QEMU_ARM:-qemu-arm}
DEBUGFS=${DEBUGFS:-debugfs}
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
# The extracted directory alone is not a cryptographic identity for the full
# target filesystem. Require the retained rootfs image so the verifier can bind
# L2 to the canonical image SHA-256, not merely to a few selected runtime files.
[ -n "$ROOTFS_IMAGE" ] || {
  echo "ROOTFS_IMAGE=<checksum-verified PW6 rootfs image> is required for exact-rootfs QEMU" >&2
  exit 66
}
[ -f "$ROOTFS_IMAGE" ] || {
  echo "PW6 rootfs image is missing or not a regular file: $ROOTFS_IMAGE" >&2
  exit 66
}
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

# Once an invocation reaches the dynamic L2 phase, invalidate any prior PASS
# in the same output directory before doing work. A failed rerun must never
# leave an older QEMU-SMOKE.txt / provenance pair available for packaging.
mkdir -p "$OUT"
rm -f "$OUT/QEMU-SMOKE.txt" "$OUT/QEMU-PROVENANCE.txt" \
  "$OUT/rootfs-verification.txt" "$OUT/input-rootfs-verification.txt" \
  "$OUT/backend-smoke.txt" "$OUT/audio-self-test.txt" "$OUT/sync-self-test.txt" \
  "$OUT/kap-qemu-smoke"

if ! command -v "$QEMU_ARM" >/dev/null 2>&1; then
  if command -v qemu-arm-static >/dev/null 2>&1; then
    QEMU_ARM=qemu-arm-static
  else
    echo "qemu user-mode binary not found: $QEMU_ARM or qemu-arm-static" >&2
    exit 69
  fi
fi
if ! command -v "$DEBUGFS" >/dev/null 2>&1; then
  echo "debugfs is required to derive the QEMU runtime tree from ROOTFS_IMAGE" >&2
  exit 69
fi
[ -e "$ROOTFS/lib/ld-linux-armhf.so.3" ] || { echo "rootfs lacks ARMHF loader" >&2; exit 66; }
[ -r "$ARMHF/libanki-kindle.so" ] || { echo "missing ARMHF backend" >&2; exit 66; }

# Verify the supplied extracted tree for the expected PW6 runtime oracle, then
# independently re-extract the *verified retained image* and execute QEMU only
# against that image-derived tree. This closes the previous gap where a caller
# could pair the canonical image hash with an unrelated extracted directory
# containing only the few pinned runtime files.
python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" \
  "$ROOTFS" --manifest "$ROOTFS_MANIFEST" --rootfs-image "$ROOTFS_IMAGE" \
  | tee "$OUT/input-rootfs-verification.txt"

TMP_QEMU_ROOTFS=$(mktemp -d "${TMPDIR:-/tmp}/kap-qemu-rootfs.XXXXXX")
IMAGE_ROOTFS="$TMP_QEMU_ROOTFS/rootfs"
cleanup() {
  rm -rf "$TMP_QEMU_ROOTFS"
}
trap cleanup EXIT HUP INT TERM
mkdir -p "$IMAGE_ROOTFS"
if ! "$DEBUGFS" -R "rdump / $IMAGE_ROOTFS" "$ROOTFS_IMAGE" >/dev/null 2>&1; then
  echo "debugfs failed to derive QEMU runtime tree from the verified ROOTFS_IMAGE" >&2
  exit 66
fi
[ -e "$IMAGE_ROOTFS/lib/ld-linux-armhf.so.3" ] || {
  echo "image-derived PW6 rootfs lacks ARMHF loader" >&2
  exit 66
}
python3 "$PROJECT/testenv/scripts/verify-pw6-rootfs.py" \
  "$IMAGE_ROOTFS" --manifest "$ROOTFS_MANIFEST" --rootfs-image "$ROOTFS_IMAGE" \
  | tee "$OUT/rootfs-verification.txt"

"$TOOLCHAIN_BIN/$TRIPLE-gcc" -O2 -std=c99 -Wall -Wextra -Werror \
  -I"$PROJECT/core" "$PROJECT/testenv/qemu/smoke.c" -ldl -o "$OUT/kap-qemu-smoke"

# The backend expects its normal shared-library closure from the target rootfs.
# Keep production binaries unchanged; only QEMU's loader prefix is virtualized.
# IMAGE_ROOTFS is freshly rdump'ed from the exact retained image verified above.
"$QEMU_ARM" -L "$IMAGE_ROOTFS" "$OUT/kap-qemu-smoke" "$ARMHF/libanki-kindle.so" \
  | tee "$OUT/backend-smoke.txt"
"$QEMU_ARM" -L "$IMAGE_ROOTFS" "$ARMHF/kap-audio" --self-test \
  | tee "$OUT/audio-self-test.txt"
"$QEMU_ARM" -L "$IMAGE_ROOTFS" "$ARMHF/kap-sync" --self-test \
  | tee "$OUT/sync-self-test.txt"
{
  "$QEMU_ARM" --version | head -1
  printf 'source_commit=%s\n' "$BUILD_COMMIT"
  printf 'anki_commit=%s\n' "$ANKI_COMMIT"
  printf 'rootfs_manifest_id=pw6-5.19.6-rootfs-manifest.json\n'
  printf 'rootfs_manifest_sha256=%s\n' "$(sha256sum "$ROOTFS_MANIFEST" | awk '{print $1}')"
  printf 'rootfs_input_verified=true\n'
  printf 'rootfs_verified=true\n'
  printf 'rootfs_runtime_source=verified-image-rdump\n'
  printf 'rootfs_image_sha256=%s\n' "$(sha256sum "$ROOTFS_IMAGE" | awk '{print $1}')"
  for binary in libanki-kindle.so kap-app kap-audio kap-sync; do
    printf '%s_sha256=%s\n' "$binary" "$(sha256sum "$ARMHF/$binary" | awk '{print $1}')"
  done
} > "$OUT/QEMU-PROVENANCE.txt"
printf 'QEMU smoke: PASS\n' | tee "$OUT/QEMU-SMOKE.txt"
