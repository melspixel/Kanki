#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT"
if [ ! -f third_party.lock.json ]; then
  echo "missing third_party.lock.json" >&2
  exit 1
fi

LOCK_NODE_VERSION=$(python3 - <<'PY'
import json
print(json.load(open("third_party.lock.json", encoding="utf-8"))["node"]["version"])
PY
)
LOCK_NODE_SHA=$(python3 - <<'PY'
import json
print(json.load(open("third_party.lock.json", encoding="utf-8"))["node"]["sha256"])
PY
)
LOCK_JSDOM_VERSION=$(python3 - <<'PY'
import json
print(json.load(open("third_party.lock.json", encoding="utf-8"))["jsdom"]["version"])
PY
)
LOCK_JSDOM_INTEGRITY=$(python3 - <<'PY'
import json
print(json.load(open("third_party.lock.json", encoding="utf-8"))["jsdom"]["integrity"])
PY
)
NODE=$(command -v node || true)
NPM=$(command -v npm || true)
if [ -z "$NODE" ] || [ -z "$NPM" ]; then
  echo "node/npm missing" >&2
  exit 1
fi
NODE_VERSION=$($NODE --version)
if [ "$NODE_VERSION" != "$LOCK_NODE_VERSION" ]; then
  echo "node version mismatch: expected $LOCK_NODE_VERSION, got $NODE_VERSION" >&2
  exit 1
fi
ACTUAL_NODE_SHA=$(sha256sum "$NODE" | awk '{print $1}')
if [ "$ACTUAL_NODE_SHA" != "$LOCK_NODE_SHA" ]; then
  echo "node sha256 mismatch" >&2
  exit 1
fi
if [ ! -f package-lock.json ]; then
  echo "missing package-lock.json" >&2
  exit 1
fi
python3 - "$LOCK_JSDOM_VERSION" "$LOCK_JSDOM_INTEGRITY" <<'PY'
import json, sys
lock = json.load(open("package-lock.json", encoding="utf-8"))
version, integrity = sys.argv[1:]
root = lock.get("packages", {}).get("node_modules/jsdom", {})
if root.get("version") != version or root.get("integrity") != integrity:
    raise SystemExit("package-lock jsdom pin mismatch")
PY
if [ ! -d node_modules/jsdom ]; then
  if [ "${KANKI_ALLOW_NPM_CI:-0}" = "1" ]; then
    npm ci --ignore-scripts --no-audit --no-fund
  else
    echo "node_modules missing; provision with npm ci from pinned cache or set KANKI_ALLOW_NPM_CI=1 in a networked environment" >&2
    exit 1
  fi
fi
INSTALLED_JSDOM_VERSION=$(node -e 'process.stdout.write(require("./node_modules/jsdom/package.json").version)')
if [ "$INSTALLED_JSDOM_VERSION" != "$LOCK_JSDOM_VERSION" ]; then
  echo "installed jsdom version mismatch" >&2
  exit 1
fi

if [ ! -f bridge/generated/anki_i18n_pb.rs ]; then
  echo "generated Anki i18n protobuf source missing; run tools/generate_anki_i18n.sh first" >&2
  exit 1
fi
python3 tests/anki_i18n_determinism_contract.py

# Shell and Python syntax.
for file in scripts/*.sh tools/*.sh; do sh -n "$file"; done
python3 -m py_compile tools/*.py tests/*.py
python3 tests/bridge_source_contract.py
python3 tests/audio_source_contract.py
python3 tests/operation_lock_source_contract.py
python3 tests/rootfs_audit_source_contract.py
python3 tests/runtime_preflight_contract.py

# Native compile contracts.
for file in device/*.c; do
  cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror -c "$file" -Ibridge -o "/tmp/$(basename "$file").o"
done
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror \
  -o /tmp/kanki-audio-test device/kanki_audio.c -ldl
/tmp/kanki-audio-test --self-test
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror \
  -o /tmp/kanki-audio-runtime-contract tests/audio_runtime_contract.c -ldl
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror \
  -o /tmp/kanki-operation-lock-host tests/flock_fd.c

# Full native audio runtime contract with fake GStreamer/GObject shared libraries.
sh tests/audio_runtime_contract.sh

# Cross-process collection ownership contract (kernel advisory lock).
sh tests/operation_lock_contract.sh

# Native sync CLI option parser must reject contradictory destructive directions.
python3 tests/sync_cli_contract.py

# Host-side native/runtime helpers that do not require display hardware.
cc -std=c11 -D_POSIX_C_SOURCE=200809L -fsigned-char -Wall -Wextra -Werror \
  -Ibridge tests/device_css_lifecycle_contract.c -o /tmp/kanki-device-css-lifecycle-contract
/tmp/kanki-device-css-lifecycle-contract

# JavaScript runtime contracts.
node tests/renderer_contract.test.cjs
node tests/css_compat.test.cjs
node tests/audio_protocol_contract.test.cjs
node tests/navigation_contract.test.cjs
node tests/diagnostics_contract.test.cjs

# Production bridge plus the real pinned Anki core.
if [ ! -f build/host/libanki-kanki.so ]; then
  echo "host backend missing; run tools/run_anki_bridge_host.sh first" >&2
  exit 1
fi
BACKEND=$(pwd)/build/host/libanki-kanki.so
KANKI_BACKEND="$BACKEND" node tests/apkg_reviewer_contract.test.cjs
KANKI_TEST_LIBRARY="$BACKEND" python3 tests/anki_bridge_integration.py
KANKI_TEST_LIBRARY="$BACKEND" python3 tests/apkg_bridge_integration.py
KANKI_TEST_LIBRARY="$BACKEND" python3 tests/sync_bridge_integration.py

# Packaging, integrity and report privacy are also host contracts.
KANKI_PACKAGE_DIR="${KANKI_PACKAGE_DIR:-build/package/Kanki}"
KANKI_ZIP_PATH="${KANKI_ZIP_PATH:-build/package/Kanki.zip}"
KANKI_REPORT_PATH="${KANKI_REPORT_PATH:-build/package/REPORT.txt}"
if [ -d "$KANKI_PACKAGE_DIR" ]; then
  python3 tools/verify_package_manifest.py "$KANKI_PACKAGE_DIR"
  sh tests/install_integrity_contract.sh
  if [ -f "$KANKI_ZIP_PATH" ]; then
    python3 tests/reproducible_zip_contract.py "$KANKI_ZIP_PATH"
  fi
fi
if [ -f "$KANKI_REPORT_PATH" ]; then
  python3 tests/report_privacy_contract.py "$KANKI_REPORT_PATH"
fi

# A real PW6 rootfs may be supplied for dynamic-loader verification. The path is
# intentionally not persisted in repository state or reports.
if [ -n "${KANKI_PW6_ROOTFS:-}" ]; then
  sh tools/audit_pw6_rootfs.sh "$KANKI_PW6_ROOTFS"
fi

printf '%s\n' 'host gates: pass'
