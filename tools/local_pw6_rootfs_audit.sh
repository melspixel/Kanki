#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${KANKI_PW6_AUDIT_IMAGE:-kanki-pw6-rootfs-audit:ubuntu24.04}
PLATFORM=${KANKI_PW6_AUDIT_PLATFORM:-linux/amd64}
KINDLETOOL_COMMIT=4d559f6c5b3ebf7dd2d5cfb26c7fd9a601234eda

fail() {
    echo "kanki-pw6-audit: $*" >&2
    exit 1
}

if ! command -v docker >/dev/null 2>&1; then
    fail "docker CLI is required (Docker Desktop, OrbStack, Colima, or compatible daemon)"
fi
if ! docker info >/dev/null 2>&1; then
    fail "Docker daemon is not running"
fi

cd "$ROOT"
test "$(git branch --show-current)" = rewrite-v1 ||
    fail "run the PW6 audit from rewrite-v1, not $(git branch --show-current)"

if [ -n "$(git status --porcelain --untracked-files=normal --ignore-submodules=dirty)" ]; then
    fail "repository must be clean so package and evidence identify one exact candidate"
fi

if [ ! -e third_party/kindle-sdk/.git ]; then
    fail "Kindle SDK submodule is not initialized"
fi

printf '%s\n' '== initialize fixed KindleTool submodule =='
git -C third_party/kindle-sdk submodule update --init KindleTool
test "$(git -C third_party/kindle-sdk/KindleTool rev-parse HEAD)" = "$KINDLETOOL_COMMIT" ||
    fail "KindleTool gitlink does not match $KINDLETOOL_COMMIT"

printf '%s\n' "== build PW6 rootfs audit image ($PLATFORM) =="
docker build \
    --platform "$PLATFORM" \
    -f tools/pw6-rootfs-audit.Dockerfile \
    -t "$IMAGE" \
    tools

printf '%s\n' '== audit canonical package against official PW6 5.19.6 rootfs =='
docker run --rm \
    --platform "$PLATFORM" \
    -e KANKI_ROOT=/work \
    -e KANKI_PACKAGE_ROOT=/work/out/local-kindle/package \
    -v "$ROOT:/work" \
    -w /work \
    "$IMAGE" \
    bash -lc '
      git config --global --add safe.directory /work
      git config --global --add safe.directory /work/third_party/kindle-sdk
      git config --global --add safe.directory /work/third_party/kindle-sdk/KindleTool
      bash tools/audit_pw6_rootfs.sh
    '
