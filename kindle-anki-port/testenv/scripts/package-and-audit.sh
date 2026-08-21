#!/usr/bin/env bash
set -euo pipefail

# Package metadata must not depend on the caller's umask.
umask 022

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the directory from run-armhf-gates.sh}
DIST=${DIST:-$PROJECT/build/package-root}
RELEASE=${RELEASE:-$PROJECT/release}
VERSION=${VERSION:-0.1.0-dev}
BUILD_COMMIT=${BUILD_COMMIT:-$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null || true)}
ANKI_COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$PROJECT/upstream.lock.json")

# The package provenance must name an immutable source commit. If a Git checkout
# is available, also require the checked-out project tree to match it exactly;
# ignored build/release outputs do not make the source tree dirty.
if ! printf '%s\n' "$BUILD_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  echo "BUILD_COMMIT must be a full lowercase 40-hex Git commit" >&2
  exit 65
fi
if PROJECT_HEAD=$(git -C "$PROJECT" rev-parse HEAD 2>/dev/null); then
  if [ "$PROJECT_HEAD" != "$BUILD_COMMIT" ]; then
    echo "BUILD_COMMIT does not match project HEAD: $BUILD_COMMIT != $PROJECT_HEAD" >&2
    exit 66
  fi
  if [ -n "$(git -C "$PROJECT" status --porcelain --untracked-files=all -- .)" ]; then
    echo "project source tree is dirty; refusing release packaging" >&2
    git -C "$PROJECT" status --short --untracked-files=all -- . >&2 || true
    exit 66
  fi
fi

# Never relabel stale cross-build outputs as a package from a newer source head.
for required in kap-app kap-audio kap-sync libanki-kindle.so file.txt exports.txt ARMHF-GATES.txt BUILD-PROVENANCE.txt; do
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

# A reproducible ZIP needs both a clean output tree and a stable DOS timestamp.
# Prefer an explicitly supplied epoch; otherwise bind it to the Git commit that
# identifies this build. Fail closed instead of silently using wall-clock time.
if [ -z "${SOURCE_DATE_EPOCH:-}" ]; then
  SOURCE_DATE_EPOCH=$(git -C "$PROJECT" show -s --format=%ct "$BUILD_COMMIT" 2>/dev/null || true)
fi
case "$SOURCE_DATE_EPOCH" in
  ''|*[!0-9]*)
    echo "SOURCE_DATE_EPOCH must be an integer, or BUILD_COMMIT must resolve in PROJECT" >&2
    exit 65
    ;;
esac
# ZIP DOS timestamps cover 1980-01-01 through 2107-12-31 23:59:58 UTC.
if [ "$SOURCE_DATE_EPOCH" -lt 315532800 ]; then
  echo "SOURCE_DATE_EPOCH predates the ZIP timestamp epoch: $SOURCE_DATE_EPOCH" >&2
  exit 65
fi
if [ "$SOURCE_DATE_EPOCH" -gt 4354819198 ]; then
  echo "SOURCE_DATE_EPOCH exceeds the ZIP timestamp range: $SOURCE_DATE_EPOCH" >&2
  exit 65
fi

# Both staging and release output are owned by this invocation. Reusing an
# existing ZIP lets `zip` retain members that disappeared from the new staging
# tree, and stale sidecar reports can make a checkpoint look newer than it is.
rm -rf "$DIST" "$RELEASE"
mkdir -p "$DIST/extensions/kindle-anki-port" "$DIST/documents" "$RELEASE"
EXT="$DIST/extensions/kindle-anki-port"
cp "$ARMHF/kap-app" "$ARMHF/kap-audio" "$ARMHF/kap-sync" \
   "$ARMHF/libanki-kindle.so" "$EXT/"
cp -R "$PROJECT/web" "$PROJECT/scripts" "$EXT/"
cp "$PROJECT/packaging/config.example.ini" "$EXT/config.example.ini"
cp "$PROJECT/packaging/documents/"* "$DIST/documents/"
cp "$PROJECT/LICENSE" "$EXT/"
cp "$PROJECT/packaging/README-KINDLE.md" "$EXT/README.md"

# Normalize every archived mode explicitly. GNU/POSIX cp otherwise applies the
# invoking umask when creating destination files, which changes ZIP external
# attributes even when all file bytes and SOURCE_DATE_EPOCH are identical.
find "$DIST" -type f -exec chmod 0644 {} +
chmod 755 "$EXT/kap-app" "$EXT/kap-audio" "$EXT/kap-sync" \
  "$EXT/scripts/"*.sh "$DIST/documents/"*.sh
printf '{"product":"Kindle Anki Port","version":"%s","build_commit":"%s","anki_commit":"%s","target":"armv7-unknown-linux-gnueabihf"}\n' \
  "$VERSION" "$BUILD_COMMIT" "$ANKI_COMMIT" > "$EXT/BUILD.json"
(
  cd "$EXT"
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
  sha256sum -c MANIFEST.sha256
)

# Normalize every archived file after MANIFEST generation. The manifest hashes
# bytes, not metadata, so this does not invalidate it. Python avoids GNU-touch
# date parsing differences between build hosts.
python3 - "$DIST" "$SOURCE_DATE_EPOCH" <<'PY'
import os
import sys
from pathlib import Path

root = Path(sys.argv[1])
epoch = int(sys.argv[2])
for path in root.rglob("*"):
    if path.is_symlink():
        raise SystemExit(f"package staging must not contain symlinks: {path}")
    if path.is_file():
        os.utime(path, (epoch, epoch))
PY

ARCHIVE="$RELEASE/Kindle-Anki-Port-PW6-armhf.zip"
(
  cd "$DIST"
  # Info-ZIP serializes DOS timestamps in local civil time. Pin UTC or the same
  # SOURCE_DATE_EPOCH produces different archive bytes in different timezones.
  export TZ=UTC
  # Feed an explicitly sorted file list so filesystem/readdir ordering cannot
  # perturb the central directory. Controlled package paths never contain LF.
  find extensions documents -type f -print | LC_ALL=C sort | zip -X -q "$ARCHIVE" -@
)
python3 "$PROJECT/tools/audit_package.py" "$ARCHIVE" \
  --sha256-out "$ARCHIVE.sha256"
python3 "$PROJECT/tests/test_package_policy.py" "$ARCHIVE"
unzip -t "$ARCHIVE"
unzip -l "$ARCHIVE" > "$RELEASE/package-contents.txt"
cp "$ARMHF/file.txt" "$ARMHF/exports.txt" "$ARMHF/ARMHF-GATES.txt" \
  "$ARMHF/BUILD-PROVENANCE.txt" "$RELEASE/"
cp "$ARMHF"/*.abi.txt "$ARMHF"/*.glibc.txt "$RELEASE/"
printf 'build_commit=%s\nanki_commit=%s\nsource_date_epoch=%s\narchive_sha256=%s\n' \
  "$BUILD_COMMIT" "$ANKI_COMMIT" "$SOURCE_DATE_EPOCH" "$(sha256sum "$ARCHIVE" | awk '{print $1}')" \
  > "$RELEASE/PACKAGE-PROVENANCE.txt"
printf '%s\n' "$ARCHIVE"
