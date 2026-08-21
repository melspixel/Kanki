#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/testenv/tests/audio/fake_gstreamer.c" \
    -Wl,-soname,libgstreamer-0.10.so.0 -o "$TMP/libgstreamer-0.10.so.0"
cc -shared -fPIC -O2 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/testenv/tests/audio/fake_gobject.c" \
    -Wl,-soname,libgobject-2.0.so.0 -o "$TMP/libgobject-2.0.so.0"
cc -O2 -std=c99 -Wall -Wextra -Werror \
    "$PROJECT_ROOT/native/audio.c" -ldl -o "$TMP/kap-audio"
KAP_FAKE_GST_LOG="$TMP/gst.log" LD_LIBRARY_PATH="$TMP" \
    "$TMP/kap-audio" --probe | grep -q KAP_AUDIO_PROBE_OK
touch "$TMP/test.mp3"
KAP_FAKE_GST_LOG="$TMP/gst.log" LD_LIBRARY_PATH="$TMP" \
    "$TMP/kap-audio" "$TMP/test.mp3"
grep -q 'factory=playbin2' "$TMP/gst.log"
grep -q 'factory=mixersink' "$TMP/gst.log"
printf 'PLAY\t%s\nQUIT\n' "$TMP/test.mp3" \
    | KAP_FAKE_GST_LOG="$TMP/gst.log" LD_LIBRARY_PATH="$TMP" "$TMP/kap-audio" \
    | grep -q 'RESULT[[:space:]]0'
