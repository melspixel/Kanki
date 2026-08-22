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
    env_readme = (ROOT / "testenv" / "README.md").read_text(encoding="utf-8")
    static_gates = (ROOT / "testenv" / "scripts" / "run-static-gates.sh").read_text(encoding="utf-8")
    host_compat = (ROOT / "testenv" / "scripts" / "run-host-gates.sh").read_text(encoding="utf-8")
    package_compat = (ROOT / "testenv" / "scripts" / "package_audit.py").read_text(encoding="utf-8")
    workflow = (REPO / ".github" / "workflows" / "kindle-anki-port.yml").read_text(encoding="utf-8")
    test_environment = (ROOT / "docs" / "TEST_ENVIRONMENT.md").read_text(encoding="utf-8")
    release_gates = (ROOT / "docs" / "RELEASE_GATES.md").read_text(encoding="utf-8")

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
    # bytes that have not passed the current QEMU release gate. Exact-rootfs L2
    # additionally requires the retained image bytes so the full image SHA can
    # be verified, not just a selected-file oracle from an extracted directory.
    require(top_make, "ROOTFS_IMAGE ?=", "top-level Makefile")
    require(top_make, "QEMU ?= $(PROJECT_ROOT)/$(BUILD)/qemu", "top-level Makefile")
    require(top_make, 'ROOTFS_IMAGE=<retained checksum-verified PW6 rootfs image> is required', "top-level Makefile qemu-smoke")
    require(top_make, 'ROOTFS_IMAGE="$(ROOTFS_IMAGE)"', "top-level Makefile qemu-smoke")
    require(top_make, 'OUT="$(QEMU)"', "top-level Makefile qemu-smoke")
    require(top_make, 'BUILD_COMMIT="$(BUILD_COMMIT)"', "top-level Makefile qemu-smoke")
    require(top_make, 'QEMU=<fresh run-qemu-smoke output directory> is required', "top-level Makefile package")
    require(top_make, 'QEMU="$(QEMU)"', "top-level Makefile package")

    require(env_make, 'ANKI="$(ANKI_ROOT)"', "testenv Makefile")
    require(env_make, 'TOOLCHAIN_BIN="$(TOOLCHAIN_BIN)"', "testenv Makefile")
    require(env_make, 'ROOTFS_IMAGE="$(ROOTFS_IMAGE)"', "testenv Makefile")
    require(env_make, 'python3 scripts/package_audit.py --package "$(PACKAGE)"', "testenv Makefile")
    require(env_make, 'sh "$(PROJECT_ROOT)/tests/test_zombie_operation_lock.sh"', "testenv Makefile")

    # GitHub's contents API does not preserve executable bits for every shell
    # fixture. Static gates must invoke non-executable test scripts explicitly
    # through sh, so a clean archive/checkout behaves the same as a developer
    # worktree with locally repaired modes.
    require(
        static_gates,
        'run sh "$ROOT/tests/test_sync_wrapper_signal.sh"',
        "static gate shell portability",
    )
    require(
        static_gates,
        'run sh "$ROOT/tests/test_sync_worker.sh"',
        "static gate shell portability",
    )
    forbid(
        static_gates,
        'run "$ROOT/tests/test_sync_wrapper_signal.sh"',
        "static gate shell portability",
    )
    forbid(
        static_gates,
        'run "$ROOT/tests/test_sync_worker.sh"',
        "static gate shell portability",
    )

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

    # Required continuation/test-policy docs must describe the same release
    # ordering as the executable entrypoints. Package construction belongs after
    # exact-rootfs QEMU, and physical PW6 HIL remains a separate result.
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

    require(env_readme, "`scripts/run-qemu-smoke.sh`", "testenv README")
    require(env_readme, "`scripts/package-and-audit.sh`", "testenv README")
    require(env_readme, "**only after step 5 passes**", "testenv README")
    require(env_readme, "do not create a final-looking `Kindle-Anki-Port-PW6-armhf.zip`", "testenv README")
    qemu_doc = env_readme.index("`scripts/run-qemu-smoke.sh`")
    package_doc = env_readme.index("`scripts/package-and-audit.sh`")
    if not qemu_doc < package_doc:
        raise AssertionError("testenv README documents package before exact-rootfs QEMU")

    require(release_gates, "5. L1 ARMHF/ABI:", "release gates")
    require(release_gates, "6. L2 exact-rootfs QEMU:", "release gates")
    require(release_gates, "7. L2.5 package/privacy/reproducibility:", "release gates")
    require(release_gates, "only after L2 PASS", "release gates")
    require(release_gates, "must not be assembled before the exact-rootfs L2 gate passes", "release gates")
    require(release_gates, "## Hardware acceptance — separate from software delivery", "release gates")
    require(release_gates, "Hardware acceptance is recorded as a distinct physical-device result", "release gates")
    rg_l1 = release_gates.index("5. L1 ARMHF/ABI:")
    rg_l2 = release_gates.index("6. L2 exact-rootfs QEMU:")
    rg_l25 = release_gates.index("7. L2.5 package/privacy/reproducibility:")
    rg_hil = release_gates.index("## Hardware acceptance — separate from software delivery")
    if not rg_l1 < rg_l2 < rg_l25 < rg_hil:
        raise AssertionError("release gates are not ordered L1 -> L2 -> L2.5 -> separate HIL")

    print("test_build_entrypoints: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
