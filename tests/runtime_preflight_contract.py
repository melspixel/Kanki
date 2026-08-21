#!/usr/bin/env python3
"""Keep untrusted runtime paths behind package-integrity verification."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def fail(message: str) -> None:
    raise SystemExit(f"runtime preflight contract: FAIL: {message}")


def require_before(name: str, text: str, earlier: str, later: str) -> None:
    try:
        earlier_at = text.index(earlier)
        later_at = text.index(later)
    except ValueError as error:
        fail(f"{name}: missing contract marker: {error}")
    if earlier_at >= later_at:
        fail(f"{name}: {earlier!r} must execute before {later!r}")


launch = (ROOT / "scripts/kanki-launch.sh").read_text(encoding="utf-8")
launch_call = "\nverify_installation\n"
require_before("launch", launch, launch_call, 'if ! mkdir "$LOCK"')
try:
    launch_verify_body = launch.split("verify_installation() {", 1)[1].split(
        "\n}\n\nverify_installation", 1
    )[0]
except IndexError:
    fail("launch: cannot isolate verify_installation body")
if '>>"$LOG"' in launch_verify_body:
    fail("launch: verifier failure path writes kanki.log before trust is established")

sync = (ROOT / "scripts/kanki-sync.sh").read_text(encoding="utf-8")
sync_verify = 'if sh "$DIR/kanki-verify.sh" "$DIR"'
require_before("sync", sync, sync_verify, 'if [ -d "$LOCK" ]')
require_before("sync", sync, sync_verify, '>>"$LOG"')

report = (ROOT / "scripts/kanki-report.sh").read_text(encoding="utf-8")
report_verify = 'if sh "$DIR/kanki-verify.sh" "$DIR"'
require_before("report", report, report_verify, 'mkdir -p "$WORK"')
require_before("report", report, report_verify, 'copy_if_readable "$DIR/BUILD.json"')

verifier = (ROOT / "scripts/kanki-verify.sh").read_text(encoding="utf-8")
require_before(
    "verifier",
    verifier,
    '(cd "$DIR" && find . -type l -print | sort)',
    '(cd "$DIR" && sha256sum -c MANIFEST.sha256)',
)

print("runtime preflight contract: pass")
