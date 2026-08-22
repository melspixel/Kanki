#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/kanki-device-css-lifecycle.XXXXXX)
trap 'rm -rf "$WORK"' EXIT HUP INT TERM

cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror \
    -I"$ROOT/bridge" "$ROOT/tests/device_css_lifecycle_contract.c" \
    -o "$WORK/device-css-lifecycle-contract"
"$WORK/device-css-lifecycle-contract"
