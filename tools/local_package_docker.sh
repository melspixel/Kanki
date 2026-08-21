#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${KANKI_LOCAL_IMAGE:-kanki-local-builder:ubuntu24.04-rust1.92.0}
PLATFORM=${KANKI_LOCAL_PLATFORM:-linux/amd64}
TARGET_VOLUME=${KANKI_LOCAL_TARGET_VOLUME:-kanki-local-anki-target}

if ! command -v docker >/dev/null 2>&1; then
    echo "kanki-local: docker CLI is required (Docker Desktop, OrbStack, Colima, or compatible daemon)" >&2
    exit 69
fi

if ! docker info >/dev/null 2>&1; then
    echo "kanki-local: Docker daemon is not running" >&2
    exit 70
fi

cd "$ROOT"

if [ ! -d third_party/anki ] || [ ! -e third_party/anki/.git ]; then
    echo "kanki-local: repository submodules are not initialized; run:" >&2
    echo "  git submodule update --init third_party/anki third_party/kindle-sdk third_party/audiobook-koplugin third_party/ranki-reference" >&2
    exit 71
fi

printf '%s\n' "== build local builder image ($PLATFORM) =="
docker build \
    --platform "$PLATFORM" \
    -f tools/local-builder.Dockerfile \
    -t "$IMAGE" \
    tools

printf '%s\n' '== build Kanki Kindle package locally =='
docker run --rm \
    --platform "$PLATFORM" \
    -e RUSTUP_HOME=/opt/rustup \
    -e CARGO_HOME=/cache/cargo \
    -e HOME=/cache/home \
    -e KANKI_OUT_DIR=/work/out/local-kindle \
    -v "$ROOT:/work" \
    -v kanki-local-cargo:/cache/cargo \
    -v kanki-local-home:/cache/home \
    --mount "type=volume,src=$TARGET_VOLUME,dst=/work/third_party/anki/target,volume-nocopy" \
    -w /work \
    "$IMAGE" \
    bash -lc '
      git config --global --add safe.directory /work
      git config --global --add safe.directory /work/third_party/anki
      git config --global --add safe.directory /work/third_party/kindle-sdk
      git config --global --add safe.directory /work/third_party/audiobook-koplugin
      git config --global --add safe.directory /work/third_party/ranki-reference
      bash tools/build_kindle_package.sh
    '

printf '\nLocal package is in:\n  %s\n' "$ROOT/out/local-kindle"
