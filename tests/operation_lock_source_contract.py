#!/usr/bin/env python3
"""Keep reviewer and sync collection ownership on one inherited kernel lock."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
HELPER = (ROOT / "scripts/kanki-operation-lock.sh").read_text(encoding="utf-8")
LAUNCH = (ROOT / "scripts/kanki-launch.sh").read_text(encoding="utf-8")
SYNC = (ROOT / "scripts/kanki-sync.sh").read_text(encoding="utf-8")
VERIFY = (ROOT / "scripts/kanki-verify.sh").read_text(encoding="utf-8")
PACKAGE = (ROOT / "tools/build_kindle_package.sh").read_text(encoding="utf-8")
ROOTFS = (ROOT / "tools/audit_pw6_rootfs.sh").read_text(encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit(f"collection operation lock source contract: FAIL: {message}")


def require(text: str, fragment: str, message: str) -> None:
    if fragment not in text:
        fail(message)


def forbid(text: str, fragment: str, message: str) -> None:
    if fragment in text:
        fail(message)


for fragment in [
    'exec 9<>"$KANKI_OPERATION_LOCK_FILE"',
    '"${KANKI_FLOCK:-/usr/bin/flock}" -n -E 74 9',
    "kanki_operation_lock_validate_inherited()",
    'readlink -f "/proc/$$/fd/9"',
    "KANKI_OPERATION_LOCK_LOCAL_OWNER",
]:
    require(HELPER, fragment, f"shared lock helper is missing: {fragment}")

for text, mode, name in [(LAUNCH, "launch", "launcher"), (SYNC, "sync", "sync")]:
    require(
        text,
        'KANKI_OPERATION_LOCK_FILE="$DIR/.kanki.operation.lock"',
        f"{name} does not use the manifest-owned operation lock",
    )
    require(
        text,
        f"kanki_operation_lock_acquire {mode}",
        f"{name} does not atomically acquire its collection operation mode",
    )

require(
    LAUNCH,
    'KANKI_OPERATION_LOCK_OWNER=$$',
    "launcher does not identify the exact inherited sync handoff owner",
)
require(
    LAUNCH,
    '"$DIR/kanki-diag" 9>&-',
    "diagnostics child can accidentally prolong the collection lock",
)
require(
    LAUNCH,
    '"$DIR/kanki-audio" 9>&-',
    "audio child can accidentally prolong the collection lock",
)
require(
    SYNC,
    "kanki_operation_lock_validate_inherited",
    "launcher-initiated sync does not validate the inherited descriptor",
)
forbid(
    SYNC,
    'if [ -d "$LOCK" ]',
    "sync reverted to a racy lock-path existence check",
)
for text, name in [(LAUNCH, "launcher"), (SYNC, "sync")]:
    for signal in ["HUP", "INT", "TERM"]:
        require(text, f"forward_signal {signal}", f"{name} does not forward {signal}")

require(
    VERIFY,
    "./.kanki.lock/mode",
    "install verifier does not bound operation metadata",
)
for fragment in [
    "scripts/kanki-operation-lock.sh",
    'packaging/kanki.operation.lock "$EXT/.kanki.operation.lock"',
]:
    require(PACKAGE, fragment, f"canonical package omits operation lock input: {fragment}")
for fragment in [
    "operation-lock-pw6-busybox.txt",
    "collection_operation_lock_pw6_busybox=pass",
]:
    require(ROOTFS, fragment, f"PW6 rootfs audit omits lock evidence: {fragment}")

print("collection operation lock source contract: pass")
