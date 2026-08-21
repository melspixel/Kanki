#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
BUILD=${KAP_BUILD_DIR:-$ROOT/build/static-gates}
CC=${CC:-cc}
mkdir -p "$BUILD"
LOCK="$BUILD/.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
    echo "another static-gate run owns $LOCK" >&2
    exit 73
fi
REPORT="$BUILD/report.txt"
CURRENT_LOG=""
cleanup() {
    [ -z "$CURRENT_LOG" ] || rm -f "$CURRENT_LOG"
    rmdir "$LOCK" 2>/dev/null || true
}
trap cleanup EXIT HUP INT TERM
: >"$REPORT"
run() {
    printf '+ %s\n' "$*" | tee -a "$REPORT"
    CURRENT_LOG=$(mktemp "$BUILD/step.XXXXXX")
    if "$@" >"$CURRENT_LOG" 2>&1; then
        cat "$CURRENT_LOG" | tee -a "$REPORT"
        rm -f "$CURRENT_LOG"
        CURRENT_LOG=""
    else
        status=$?
        cat "$CURRENT_LOG" | tee -a "$REPORT"
        rm -f "$CURRENT_LOG"
        CURRENT_LOG=""
        printf 'FAILED status=%s: %s\n' "$status" "$*" | tee -a "$REPORT" >&2
        return "$status"
    fi
}

run python3 -m py_compile \
    "$ROOT/tools/inject_into_anki.py" "$ROOT/tools/audit_package.py" \
    "$ROOT/tools/audit_generated_services.py" \
    "$ROOT/testenv/scripts/package_audit.py" \
    "$ROOT/testenv/scripts/prepare-pw6-rootfs.py" \
    "$ROOT/testenv/scripts/verify-pw6-rootfs.py" \
    "$ROOT/testenv/scripts/vm-advance.py" \
    "$ROOT/tests/test_core_integration.py" \
    "$ROOT/tests/test_injector.py" "$ROOT/tests/test_semantic_boundary.py" \
    "$ROOT/tests/test_source_contract.py" "$ROOT/tests/test_package_audit.py" \
    "$ROOT/tests/test_package_reproducibility.py" "$ROOT/tests/test_armhf_provenance.py" \
    "$ROOT/tests/test_prepare_pw6_rootfs.py" "$ROOT/tests/test_rootfs_prepare_script.py" \
    "$ROOT/tests/test_build_entrypoints.py" "$ROOT/tests/test_prepare_sysroot.py" \
    "$ROOT/tests/test_vm_advance_contract.py"
run python3 "$ROOT/tests/test_injector.py"
run python3 "$ROOT/tests/test_semantic_boundary.py"
run python3 "$ROOT/tests/test_source_contract.py"
run python3 "$ROOT/tests/test_package_audit.py"
run python3 "$ROOT/tests/test_package_reproducibility.py"
run python3 "$ROOT/tests/test_armhf_provenance.py"
run python3 "$ROOT/tests/test_prepare_pw6_rootfs.py"
run python3 "$ROOT/tests/test_rootfs_prepare_script.py"
run python3 "$ROOT/tests/test_build_entrypoints.py"
run python3 "$ROOT/tests/test_prepare_sysroot.py"
run python3 "$ROOT/tests/test_vm_advance_contract.py"
run sh -n "$ROOT/testenv/scripts/prepare-pw6-rootfs.sh"
run sh -n "$ROOT/testenv/scripts/prepare-sysroot.sh"
run sh -n "$ROOT/testenv/scripts/run-host-gates.sh"
run sh -n "$ROOT/testenv/scripts/run-host-backend-gates.sh"
run sh -n "$ROOT/testenv/scripts/run-armhf-gates.sh"
run sh -n "$ROOT/testenv/scripts/run-qemu-host-sanity.sh"
run sh -n "$ROOT/testenv/scripts/run-qemu-smoke.sh"
run sh -n "$ROOT/testenv/scripts/package-and-audit.sh"
run sh -n "$ROOT/testenv/tests/audio/test-audio.sh"
run sh -n "$ROOT/testenv/tests/lifecycle/test-launcher-integration.sh"
run node --check "$ROOT/web/bridge.js"
run node --check "$ROOT/web/css_compat.js"
run node --check "$ROOT/web/decks.js"
run node --check "$ROOT/web/reviewer.js"
run node "$ROOT/tests/test_web_contract.js"
run node "$ROOT/tests/test_css_compat_fixtures.js"
run node "$ROOT/tests/test_reviewer_runtime_fixtures.js"
run sh -n "$ROOT/scripts/launch.sh"
run sh -n "$ROOT/scripts/sync.sh"
run "$CC" -O2 -std=c99 -Wall -Wextra -Werror -I"$ROOT/core" \
    "$ROOT/native/app.c" -ldl -o "$BUILD/kap-app-host"
run "$CC" -O2 -std=c99 -Wall -Wextra -Werror \
    "$ROOT/native/audio.c" -ldl -o "$BUILD/kap-audio-host"
run "$CC" -O2 -std=c99 -Wall -Wextra -Werror -I"$ROOT/core" \
    "$ROOT/native/sync.c" -ldl -o "$BUILD/kap-sync-host"
run "$BUILD/kap-audio-host" --self-test
run "$BUILD/kap-sync-host" --self-test
run sh "$ROOT/testenv/tests/audio/test-audio.sh"
run env PROJECT_ROOT="$ROOT" CC="$CC" sh "$ROOT/testenv/tests/lifecycle/test-launcher-integration.sh"
run "$ROOT/tests/test_lifecycle.sh"
run "$ROOT/tests/test_sync_wrapper_signal.sh"
run sh "$ROOT/tests/test_zombie_operation_lock.sh"
run "$ROOT/tests/test_sync_worker.sh"
if [ -n "${KAP_GENERATED_BACKEND:-}" ]; then
    run python3 "$ROOT/tools/audit_generated_services.py" "$KAP_GENERATED_BACKEND"
fi
printf 'static gates: PASS\n' | tee -a "$REPORT"
