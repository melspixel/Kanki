#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
WORK=$(mktemp -d /tmp/kanki-install-contract.XXXXXX)
PACKAGE="$WORK/kanki"

cleanup() {
    rm -rf "$WORK"
}
trap cleanup EXIT HUP INT TERM

fail() {
    printf 'install integrity contract: FAIL: %s\n' "$*" >&2
    exit 1
}

expect_status() {
    EXPECTED=$1
    shift
    if "$@" >"$WORK/failure.log" 2>&1; then
        fail "command unexpectedly passed: $*"
    else
        STATUS=$?
    fi
    if [ "$STATUS" -ne "$EXPECTED" ]; then
        cat "$WORK/failure.log" >&2
        fail "expected status $EXPECTED, got $STATUS: $*"
    fi
}

mkdir -p "$PACKAGE/assets"
printf '%s\n' '{"kanki_commit":"fixture"}' >"$PACKAGE/BUILD.json"
printf '%s\n' 'fixture executable' >"$PACKAGE/kanki-device"
printf '%s\n' 'fixture asset' >"$PACKAGE/assets/reviewer.js"
(cd "$PACKAGE" && find . -type f ! -name MANIFEST.sha256 -print0 \
    | sort -z | xargs -0 sha256sum >MANIFEST.sha256)

sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE" >"$WORK/baseline.log"
grep -q '^kanki-install-integrity=pass$' "$WORK/baseline.log" || \
    fail 'clean manifest did not report pass'

mkdir -p "$PACKAGE/.kanki.lock" "$PACKAGE/render-debug" \
    "$PACKAGE/render-debug.previous"
printf '%s\n' 'runtime config fixture' >"$PACKAGE/config.ini"
printf '%s\n' 'runtime log' >"$PACKAGE/kanki.log"
: >"$PACKAGE/enable-render-capture"
printf '%s\n' '100' >"$PACKAGE/.audio.pid"
printf '%s\n' '101' >"$PACKAGE/.diag.pid"
printf '%s\n' '102' >"$PACKAGE/.kanki.lock/pid"
printf '%s\n' 'metrics' >"$PACKAGE/render-debug/metrics.log"
printf '%s\n' 'raw bounded fixture' >"$PACKAGE/render-debug/card-1.json"
printf '%s\n' 'old metrics' >"$PACKAGE/render-debug.previous/metrics.log"
sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE" >/dev/null

printf '%s\n' 'stale old runtime' >"$PACKAGE/assets/obsolete-reviewer.js"
expect_status 73 sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE"
rm -f "$PACKAGE/assets/obsolete-reviewer.js"

printf '%s\n' 'tampered executable' >"$PACKAGE/kanki-device"
expect_status 71 sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE"
printf '%s\n' 'fixture executable' >"$PACKAGE/kanki-device"

mv "$PACKAGE/kanki-device" "$WORK/kanki-device"
expect_status 71 sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE"
mv "$WORK/kanki-device" "$PACKAGE/kanki-device"

ln -s kanki-device "$PACKAGE/legacy-device-link"
expect_status 72 sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE"
rm -f "$PACKAGE/legacy-device-link"

mv "$PACKAGE/MANIFEST.sha256" "$WORK/MANIFEST.sha256"
expect_status 70 sh "$ROOT/scripts/kanki-verify.sh" "$PACKAGE"

printf '%s\n' 'install integrity contract: pass'
