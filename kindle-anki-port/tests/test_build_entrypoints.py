#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise AssertionError(f"{label} missing required contract: {needle}")


def forbid(text: str, needle: str, label: str) -> None:
    if needle in text:
        raise AssertionError(f"{label} contains stale/weak entry point: {needle}")


def main() -> int:
    top_make = (ROOT / "Makefile").read_text(encoding="utf-8")
    env_make = (ROOT / "testenv" / "Makefile").read_text(encoding="utf-8")
    host_compat = (ROOT / "testenv" / "scripts" / "run-host-gates.sh").read_text(encoding="utf-8")
    package_compat = (ROOT / "testenv" / "scripts" / "package_audit.py").read_text(encoding="utf-8")
    workflow = (REPO / ".github" / "workflows" / "kindle-anki-port.yml").read_text(encoding="utf-8")

    for needle in (
        "$(BASH) ./testenv/scripts/run-host-backend-gates.sh",
        "$(BASH) ./testenv/scripts/run-armhf-gates.sh",
        "$(BASH) ./testenv/scripts/run-qemu-host-sanity.sh",
        "$(BASH) ./testenv/scripts/run-qemu-smoke.sh",
        "$(BASH) ./testenv/scripts/package-and-audit.sh",
    ):
        require(top_make, needle, "top-level Makefile")

    require(env_make, 'ANKI="$(ANKI_ROOT)"', "testenv Makefile")
    require(env_make, 'TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)"', "testenv Makefile")
    require(env_make, 'python3 scripts/package_audit.py --package "$(PACKAGE)"', "testenv Makefile")
    require(env_make, 'sh "$(PROJECT_ROOT)/tests/test_zombie_operation_lock.sh"', "testenv Makefile")

    require(host_compat, "run-static-gates.sh", "host compatibility wrapper")
    require(host_compat, "run-host-backend-gates.sh", "host compatibility wrapper")
    forbid(host_compat, "kap_port::tests", "host compatibility wrapper")

    require(package_compat, '"tools" / "audit_package.py"', "package compatibility wrapper")
    require(package_compat, '"tests" / "test_package_policy.py"', "package compatibility wrapper")
    forbid(package_compat, "FORBIDDEN_NAMES", "package compatibility wrapper")

    require(
        workflow,
        'bash "$PROJECT/testenv/scripts/run-qemu-host-sanity.sh"',
        "canonical workflow",
    )

    print("test_build_entrypoints: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
