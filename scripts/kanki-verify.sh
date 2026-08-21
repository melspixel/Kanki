#!/bin/sh
set -eu

DIR=${1:-/mnt/us/extensions/kanki}
MANIFEST="$DIR/MANIFEST.sha256"
TMP_PREFIX=/tmp/kanki-install-verify.$$
EXPECTED="$TMP_PREFIX.expected"
ACTUAL="$TMP_PREFIX.actual"
LINKS="$TMP_PREFIX.links"

cleanup_temp() {
    rm -f "$EXPECTED" "$ACTUAL" "$LINKS"
}
trap cleanup_temp EXIT HUP INT TERM

fail() {
    STATUS=$1
    shift
    printf 'kanki-install-integrity: %s\n' "$*" >&2
    exit "$STATUS"
}

case "$DIR" in
    ''|/) fail 70 "unsafe or empty installation directory: $DIR" ;;
esac

if [ ! -d "$DIR" ] || [ -L "$DIR" ]; then
    fail 70 "installation directory missing or symbolic: $DIR"
fi

# Refuse links before reading BUILD.json, the manifest, or any manifest-owned
# path. Callers likewise authenticate this verifier before touching runtime
# logs, locks or report inputs.
if ! (cd "$DIR" && find . -type l -print | sort) >"$LINKS"; then
    fail 70 'unable to scan installation tree for symbolic links'
fi
if [ -s "$LINKS" ]; then
    FIRST_LINK=$(sed -n '1p' "$LINKS")
    fail 72 "symbolic link is not allowed: $FIRST_LINK"
fi
if [ ! -r "$DIR/BUILD.json" ]; then
    fail 70 'build identity missing: BUILD.json'
fi
if [ ! -r "$MANIFEST" ]; then
    fail 70 'package manifest missing: MANIFEST.sha256'
fi

if ! (cd "$DIR" && sha256sum -c MANIFEST.sha256); then
    fail 71 'package manifest verification failed'
fi

cut -c 67- "$MANIFEST" | sort >"$EXPECTED"
(cd "$DIR" && find . -type f -print | sort) >"$ACTUAL"
while IFS= read -r FILE; do
    case "$FILE" in
        ./MANIFEST.sha256|./config.ini|./kanki.log|./enable-render-capture|\
        ./.audio.pid|./.diag.pid|./.kanki.lock/pid|./.kanki.lock/mode|\
        ./render-debug/*|./render-debug.previous/*)
            continue
            ;;
    esac
    if ! grep -F -x "$FILE" "$EXPECTED" >/dev/null 2>&1; then
        fail 73 "unexpected file outside package manifest: $FILE"
    fi
done <"$ACTUAL"

printf 'kanki-install-integrity=pass\n'
