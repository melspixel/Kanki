#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"

need() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "kanki-host-gates: missing required command: $1" >&2
        exit 69
    }
}

need cargo
need rustfmt
need bash
need python3
need node
need npm
need cc

printf '%s\n' '== source pins =='
test "$(git -C third_party/anki rev-parse HEAD)" = e5a6fbe27fdd4d57d5f712191b4a753032e57853
test "$(git -C third_party/ranki-reference rev-parse HEAD)" = d671ee657f0c411474d2afff3bf9cbb49be2fb44
test "$(git -C third_party/kindle-sdk rev-parse HEAD)" = b4a6c99d718a7cf74935f36105c62491b4336a61
test "$(git -C third_party/audiobook-koplugin rev-parse HEAD)" = 62edf76feb1b7f4af2f01754957e8d57eb3e7d67

printf '%s\n' '== formatting / lint / policy =='
cargo fmt --all -- --check
rustfmt --edition 2021 --check bridge/anki_bridge.rs bridge/fixture.rs
cargo clippy --workspace --all-targets -- -D warnings
python3 tools/check_policy.py
python3 tests/bridge_source_contract.py
python3 tests/audio_source_contract.py

printf '%s\n' '== native/source syntax =='
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror -fsyntax-only device/kanki_device.c -Ibridge
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror -fsyntax-only device/kanki_sync_cli.c -Ibridge
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror -fsyntax-only device/kanki_raise.c
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror -fsyntax-only device/kanki_diag_server.c
node --check assets/device/decks.js
node --check assets/reviewer/reviewer.js
node --check assets/reviewer/css_compat.js
node --check assets/reviewer/css_runtime.js
node --check assets/reviewer/diagnostics.js
node --check tests/renderer_contract.test.cjs
node --check tests/css_compat.test.cjs
node --check tests/diagnostics_contract.test.cjs
sh -n scripts/kanki-launch.sh
sh -n scripts/kanki-sync.sh
sh -n scripts/kanki-report.sh
sh -n tools/install_kindlehf_toolchain.sh
bash -n tools/run_anki_bridge_host.sh
sh -n tools/local_anki_bridge_docker.sh
sh -n tools/local_package_docker.sh
python3 -c 'compile(open("tests/anki_bridge_integration.py", encoding="utf-8").read(), "tests/anki_bridge_integration.py", "exec")'
python3 -c 'compile(open("tests/sync_bridge_integration.py", encoding="utf-8").read(), "tests/sync_bridge_integration.py", "exec")'

printf '%s\n' '== host unit/integration =='
cargo test --workspace

if [ ! -d node_modules/jsdom ]; then
    printf '%s\n' '== install pinned jsdom test dependency =='
    npm install --no-save --ignore-scripts jsdom@24.1.3
fi

printf '%s\n' '== reviewer contracts =='
node tests/renderer_contract.test.cjs
node tests/navigation_contract.test.cjs
node tests/css_compat.test.cjs
node tests/diagnostics_contract.test.cjs

printf '%s\n' '== app self-test =='
SELF=$(mktemp)
trap 'rm -f "$SELF"' EXIT INT TERM
cargo run -p kanki-app -- --self-test >"$SELF"
cat "$SELF"
grep -q '"result": "pass"' "$SELF"

printf '%s\n' 'kanki host gates: PASS'
