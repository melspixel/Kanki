#!/usr/bin/env bash
set -euo pipefail

ROOT=$(git rev-parse --show-toplevel)
PROJECT="$ROOT/kindle-anki-port/RankiRefresh"
DIST="$PROJECT/dist"
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

REPO=${GITHUB_REPOSITORY:-melspixel/Kanki}
TOKEN=${GH_TOKEN:-${GITHUB_TOKEN:-}}
RENDERER_ARTIFACT_ID=9419164966
BACKEND_ARTIFACT_ID=9418086875

if [ -z "$TOKEN" ]; then
  echo "GH_TOKEN/GITHUB_TOKEN is required to download retained Actions artifacts" >&2
  exit 2
fi

mkdir -p "$DIST"
rm -rf "$DIST/unpacked" "$DIST/Kanki-Anki26-diagnostics1.zip" \
       "$DIST/Kanki-Anki26-diagnostics1.sha256" "$DIST/BUILD_MANIFEST.txt"

api_artifact() {
  local artifact_id=$1
  local out=$2
  curl -fL --retry 4 --retry-delay 2 \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -H "X-GitHub-Api-Version: 2022-11-28" \
    "https://api.github.com/repos/$REPO/actions/artifacts/$artifact_id/zip" \
    -o "$out"
}

api_artifact "$RENDERER_ARTIFACT_ID" "$WORK/renderer-artifact.zip"
api_artifact "$BACKEND_ARTIFACT_ID" "$WORK/backend-artifact.zip"

mkdir -p "$WORK/renderer" "$WORK/backend" "$WORK/package"
unzip -q "$WORK/renderer-artifact.zip" -d "$WORK/renderer"
unzip -q "$WORK/backend-artifact.zip" -d "$WORK/backend"

test -s "$WORK/renderer/kanki.zip"
test -s "$WORK/backend/libanki-26.08-kindlehf.so"
test -s "$WORK/backend/libkanki-backend-redirect-armhf.so"

unzip -q "$WORK/renderer/kanki.zip" -d "$WORK/package"
test -d "$WORK/package/ranki"

cp "$WORK/backend/libanki-26.08-kindlehf.so" \
   "$WORK/package/ranki/libanki-26.08-armhf.so"
cp "$WORK/backend/libkanki-backend-redirect-armhf.so" \
   "$WORK/package/ranki/libkanki-backend-redirect-armhf.so"

cat > "$WORK/package/ranki/DIAGNOSTICS1_PROVENANCE.txt" <<'EOF'
RankiRefresh / Kanki Anki26 Diagnostic 1

source_ci_merge=f178e5e59e001bbf4964760d722fd6b9b10a28f1
source_tree=8fb4d25339660e1b82a984f666b2e54d7a45defa
renderer_branch_commit=ba484b13e69d04f9dc85082a399b0bd544c256d5
renderer_ci_run=32402849169
renderer_artifact_id=9419164966
backend_branch_commit=b872a164c58aa5955975169944a647fdd678e99e
backend_ci_run=32399204271
backend_artifact_id=9418086875
anki_ref=26.08
anki_commit=666c2c64d4a1772c03948f5b667438da63ddaa76
EOF

# Preserve the unpacked compiled runtime in GitHub, not just the install ZIP.
mkdir -p "$DIST/unpacked"
cp -a "$WORK/package/ranki" "$DIST/unpacked/"

(
  cd "$WORK/package"
  zip -qr "$DIST/Kanki-Anki26-diagnostics1.zip" ranki
)
sha256sum "$DIST/Kanki-Anki26-diagnostics1.zip" \
  > "$DIST/Kanki-Anki26-diagnostics1.sha256"

{
  echo "RankiRefresh Diagnostic 1 compiled-materialization manifest"
  echo "generated_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "source_ci_merge=f178e5e59e001bbf4964760d722fd6b9b10a28f1"
  echo "source_tree=8fb4d25339660e1b82a984f666b2e54d7a45defa"
  echo "renderer_artifact_id=$RENDERER_ARTIFACT_ID"
  echo "backend_artifact_id=$BACKEND_ARTIFACT_ID"
  echo "anki_ref=26.08"
  echo "anki_commit=666c2c64d4a1772c03948f5b667438da63ddaa76"
  echo
  cat "$DIST/Kanki-Anki26-diagnostics1.sha256"
  echo
  find "$DIST/unpacked/ranki" -maxdepth 1 -type f -printf '%f\t%s bytes\n' | sort
} > "$DIST/BUILD_MANIFEST.txt"

# GitHub rejects individual files >=100 MiB. Fail before attempting the push.
if find "$DIST" -type f -size +99M -print -quit | grep -q .; then
  echo "A materialized file exceeds the GitHub per-file safety limit:" >&2
  find "$DIST" -type f -size +99M -ls >&2
  exit 3
fi

printf 'Materialized RankiRefresh Diagnostic 1:\n'
cat "$DIST/Kanki-Anki26-diagnostics1.sha256"
du -sh "$DIST" "$DIST/unpacked/ranki"
