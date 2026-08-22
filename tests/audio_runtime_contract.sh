#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d "${TMPDIR:-/tmp}/kanki-audio-runtime.XXXXXX")
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

case $(uname -s) in
    Darwin)
        GST_LIBRARY="$TMP/libgstreamer-fake.dylib"
        GOBJECT_LIBRARY="$TMP/libgobject-fake.dylib"
        cc -dynamiclib -fPIC -std=c11 -Wall -Wextra -Werror \
            "$ROOT/tests/audio/fake_gstreamer.c" -o "$GST_LIBRARY"
        cc -dynamiclib -fPIC -std=c11 -Wall -Wextra -Werror \
            "$ROOT/tests/audio/fake_gobject.c" -o "$GOBJECT_LIBRARY"
        DL_FLAGS=
        ;;
    *)
        GST_LIBRARY="$TMP/libgstreamer-fake.so"
        GOBJECT_LIBRARY="$TMP/libgobject-fake.so"
        cc -shared -fPIC -std=c11 -Wall -Wextra -Werror \
            "$ROOT/tests/audio/fake_gstreamer.c" -o "$GST_LIBRARY"
        cc -shared -fPIC -std=c11 -Wall -Wextra -Werror \
            "$ROOT/tests/audio/fake_gobject.c" -o "$GOBJECT_LIBRARY"
        DL_FLAGS=-ldl
        ;;
esac

cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror \
    -I"$ROOT/device/audio" \
    "$ROOT/device/audio/kanki_audio_protocol.c" \
    "$ROOT/tests/audio_protocol_contract.c" \
    -o "$TMP/audio-protocol" -lm
"$TMP/audio-protocol"

cc -std=c11 -D_POSIX_C_SOURCE=200809L -Wall -Wextra -Werror \
    -I"$ROOT/device/audio" \
    "$ROOT/device/audio/kanki_tts_player.c" \
    "$ROOT/tests/audio_tts_runtime_contract.c" \
    -o "$TMP/audio-tts-runtime" $DL_FLAGS

KANKI_GSTREAMER_LIBRARY="$GST_LIBRARY" \
KANKI_GOBJECT_LIBRARY="$GOBJECT_LIBRARY" \
KANKI_TTS_SKIP_IVONA_PRELOAD=1 \
KANKI_FAKE_GST_LOG="$TMP/gstreamer.log" \
    "$TMP/audio-tts-runtime"

grep -Fq 'pipeline=ttssrc name=kanki_tts ! audio/x-raw' "$TMP/gstreamer.log"
grep -Fq 'mixersink stream-type=Music sync=true' "$TMP/gstreamer.log"
grep -Fq 'element=kanki_tts' "$TMP/gstreamer.log"
grep -Fq 'property=textsource value=hello "world" !' "$TMP/gstreamer.log"
grep -Fq 'property=voicelang value=en_US' "$TMP/gstreamer.log"
grep -Fq 'property=speed value=0.75' "$TMP/gstreamer.log"
grep -Fq 'state=4' "$TMP/gstreamer.log"
grep -Fq 'state=1' "$TMP/gstreamer.log"
if grep -Eq 'content-texts|property=text ' "$TMP/gstreamer.log"; then
    echo 'audio runtime contract failed: unsupported PW6 ttssrc property used' >&2
    exit 1
fi

printf '%s\n' 'audio native runtime contract: pass'
