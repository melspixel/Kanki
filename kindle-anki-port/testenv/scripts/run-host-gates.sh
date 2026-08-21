#!/bin/sh
set -eu
PROJECT_ROOT=${PROJECT_ROOT:?}
ANKI_ROOT=${ANKI_ROOT:?}
python3 -m py_compile "$PROJECT_ROOT/tools/inject_into_anki.py"
for f in "$PROJECT_ROOT"/web/*.js; do node --check "$f"; done
for f in "$PROJECT_ROOT"/scripts/*.sh; do sh -n "$f"; done
cc -O2 -std=c99 -Wall -Wextra -Werror -I"$PROJECT_ROOT/core" "$PROJECT_ROOT/native/app.c" -ldl -o /tmp/kap-app-host
cc -O2 -std=c99 -Wall -Wextra -Werror "$PROJECT_ROOT/native/audio.c" -ldl -lpthread -lm -o /tmp/kap-audio-host
(cd "$ANKI_ROOT" && PROTOC=/usr/bin/protoc CARGO_TERM_COLOR=never cargo test -p anki --features rustls kap_port::tests --lib --no-fail-fast)
(cd "$ANKI_ROOT" && PROTOC=/usr/bin/protoc CARGO_TERM_COLOR=never cargo build -p anki --features rustls --release)
nm -D "$ANKI_ROOT/target/release/libanki.so" | grep ' kap_'
