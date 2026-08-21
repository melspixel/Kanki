#!/usr/bin/env bash
set -euo pipefail

PROJECT=${PROJECT:?set PROJECT}
ARMHF=${ARMHF:?set ARMHF to the directory from run-armhf-gates.sh}
DIST=${DIST:-$PROJECT/build/package-root}
RELEASE=${RELEASE:-$PROJECT/release}
VERSION=${VERSION:-0.1.0-dev}
BUILD_COMMIT=${BUILD_COMMIT:-unknown}
ANKI_COMMIT=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["commit"])' "$PROJECT/upstream.lock.json")

# Both staging and release output are owned by this invocation.  Reusing an
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
chmod 755 "$EXT/kap-app" "$EXT/kap-audio" "$EXT/kap-sync" \
  "$EXT/scripts/"*.sh "$DIST/documents/"*.sh
printf '{"product":"Kindle Anki Port","version":"%s","build_commit":"%s","anki_commit":"%s","target":"armv7-unknown-linux-gnueabihf"}\n' \
  "$VERSION" "$BUILD_COMMIT" "$ANKI_COMMIT" > "$EXT/BUILD.json"
(
  cd "$EXT"
  find . -type f ! -name MANIFEST.sha256 -print0 | sort -z | xargs -0 sha256sum > MANIFEST.sha256
  sha256sum -c MANIFEST.sha256
)
ARCHIVE="$RELEASE/Kindle-Anki-Port-PW6-armhf.zip"
(
  cd "$DIST"
  zip -X -qr "$ARCHIVE" extensions documents
)
python3 "$PROJECT/tools/audit_package.py" "$ARCHIVE" \
  --sha256-out "$ARCHIVE.sha256"
python3 "$PROJECT/tests/test_package_policy.py" "$ARCHIVE"
unzip -t "$ARCHIVE"
unzip -l "$ARCHIVE" > "$RELEASE/package-contents.txt"
cp "$ARMHF/file.txt" "$ARMHF/exports.txt" "$ARMHF/ARMHF-GATES.txt" \
  "$ARMHF/BUILD-PROVENANCE.txt" "$RELEASE/"
cp "$ARMHF"/*.abi.txt "$ARMHF"/*.glibc.txt "$RELEASE/"
printf '%s\n' "$ARCHIVE"
