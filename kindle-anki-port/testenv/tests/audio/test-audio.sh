#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?}
CC=${CC:-cc}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

"$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/testenv/tests/audio/fake_gstreamer.c" \
    -Wl,-soname,libgstreamer-0.10.so.0 -o "$TMP/libgstreamer-0.10.so.0"
"$CC" -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/testenv/tests/audio/fake_gobject.c" \
    -Wl,-soname,libgobject-2.0.so.0 -o "$TMP/libgobject-2.0.so.0"
"$CC" -O2 -std=c99 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/native/audio.c" -ldl -o "$TMP/kap-audio"

"$TMP/kap-audio" --self-test | grep -Fqx 'kap-audio self-test: ok'

local_file="$TMP/test audio.mp3"
: >"$local_file"
: >"$TMP/gst.log"
KAP_FAKE_GST_LOG="$TMP/gst.log" LD_LIBRARY_PATH="$TMP" \
    "$TMP/kap-audio" --play "$local_file"
grep -Fqx 'factory=playbin2' "$TMP/gst.log"
grep -Fqx 'factory=mixersink' "$TMP/gst.log"
grep -F "property=uri value=file://" "$TMP/gst.log" | grep -Fq 'test%20audio.mp3'
grep -Fqx 'property=audio-sink' "$TMP/gst.log"
grep -Fqx 'state=4' "$TMP/gst.log"
grep -Fqx 'poll=eos' "$TMP/gst.log"
grep -Fqx 'state=1' "$TMP/gst.log"

: >"$TMP/gst.log"
KAP_FAKE_GST_LOG="$TMP/gst.log" LD_LIBRARY_PATH="$TMP" \
    "$TMP/kap-audio" --play 'https://example.invalid/clip.mp3'
grep -Fqx 'property=uri value=https://example.invalid/clip.mp3' "$TMP/gst.log"

set +e
"$TMP/kap-audio" "$local_file" >"$TMP/legacy.out" 2>&1
legacy_rc=$?
set -e
[ "$legacy_rc" -eq 64 ]
grep -Fq -- '--play FILE_OR_URL' "$TMP/legacy.out"

printf '%s\n' 'test-audio: ok (current --play CLI, mixersink, EOS, URI encoding)'
