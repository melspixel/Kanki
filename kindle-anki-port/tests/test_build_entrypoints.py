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
    test_environment = (ROOT / "docs" / "TEST_ENVIRONMENT.md").read_text(encoding="utf-8")

    for needle in (
        "$(BASH) ./testenv/scripts/run-host-backend-gates.sh",
        "$(BASH) ./testenv/scripts/run-armhf-gates.sh",
        "$(BASH) ./testenv/scripts/run-qemu-host-sanity.sh",
        "$(BASH) ./testenv/scripts/run-qemu-smoke.sh",
        "$(BASH) ./testenv/scripts/package-and-audit.sh",
    ):
        require(top_make, needle, "top-level Makefile")

    # Release entrypoints must preserve the source -> ARMHF -> exact-rootfs QEMU
    # -> package chain. A plain `make package` must never silently package ARMHF
    # bytes that have not passed the current QEMU release gate.
    require(top_make, "QEMU ?= $(PROJECT_ROOT)/$(BUILD)/qemu", "top-level Makefile")
    require(top_make, 'OUT="$(QEMU)"', "top-level Makefile qemu-smoke")
    require(top_make, 'BUILD_COMMIT="$(BUILD_COMMIT)"', "top-level Makefile qemu-smoke")
    require(top_make, 'QEMU=<fresh run-qemu-smoke output directory> is required', "top-level Makefile package")
    require(top_make, 'QEMU="$(QEMU)"', "top-level Makefile package")

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
    # Public CI has no proprietary PW6 rootfs bytes. It must persist an explicit
    # non-release build checkpoint instead of creating a final-looking ZIP that
    # bypasses the exact-rootfs QEMU gate.
    require(workflow, "Persist non-hardware build checkpoint", "canonical workflow")
    require(workflow, "NOT-A-RELEASE.txt", "canonical workflow")
    require(workflow, "It intentionally contains no Kindle-Anki-Port-PW6-armhf.zip.", "canonical workflow")
    require(workflow, "Final packaging requires checksum-verified PW6 5.19.6 exact-rootfs QEMU", "canonical workflow")
    if workflow.count("package-and-audit.sh") != 2:
        raise AssertionError(
            "canonical workflow should mention package-and-audit.sh only in the two explanatory checkpoint lines"
        )
    forbid(workflow, '"$PROJECT/testenv/scripts/package-and-audit.sh"', "canonical workflow")

    # TEST_ENVIRONMENT.md is a required continuation document and must describe
    # the same release ordering as the executable entrypoints. In particular,
    # package construction belongs after exact-rootfs L2, not in ARMHF L1.
    require(test_environment, "### L1 — ARMHF cross-build and static ABI audit", "test environment")
    require(test_environment, "### L2 — Exact PW6 rootfs QEMU runtime gate", "test environment")
    require(test_environment, "### L2.5 — Release package, provenance, privacy and reproducibility gate", "test environment")
    require(test_environment, "must **not** be assembled before L2 passes", "test environment")
    require(test_environment, "Public GitHub Actions do not possess the private PW6 rootfs", "test environment")
    l1 = test_environment.index("### L1 —")
    l2 = test_environment.index("### L2 —")
    l25 = test_environment.index("### L2.5 —")
    if not l1 < l2 < l25:
        raise AssertionError("test environment release layers are not ordered L1 -> L2 -> L2.5")

    print("test_build_entrypoints: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
