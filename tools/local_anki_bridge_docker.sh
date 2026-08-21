#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
IMAGE=${KANKI_LOCAL_IMAGE:-kanki-local-builder:ubuntu24.04-rust1.92.0}
PLATFORM=${KANKI_LOCAL_PLATFORM:-linux/amd64}
TARGET_VOLUME=${KANKI_LOCAL_HOST_TARGET_VOLUME:-kanki-local-anki-host-target}

if ! command -v docker >/dev/null 2>&1; then
    echo "kanki-local-host-anki: docker CLI is required" >&2
    exit 69
fi
if ! docker info >/dev/null 2>&1; then
    echo "kanki-local-host-anki: Docker daemon is not running" >&2
    exit 70
fi

cd "$ROOT"

printf '%s\n' "== build local builder image ($PLATFORM) =="
docker build \
    --platform "$PLATFORM" \
    -f tools/local-builder.Dockerfile \
    -t "$IMAGE" \
    tools

printf '%s\n' '== run typed Anki host bridge smoke locally =='
docker run --rm \
    --platform "$PLATFORM" \
    -e RUSTUP_HOME=/opt/rustup \
    -e CARGO_HOME=/cache/cargo \
    -e HOME=/cache/home \
    -e KANKI_HOST_BRIDGE_OUT_DIR=/work/out/host-anki \
    -e KANKI_ALLOW_DIRTY="${KANKI_ALLOW_DIRTY:-0}" \
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
      bash tools/run_anki_bridge_host.sh
    '

printf '\nHost Anki evidence is in:\n  %s\n' "$ROOT/out/host-anki"
