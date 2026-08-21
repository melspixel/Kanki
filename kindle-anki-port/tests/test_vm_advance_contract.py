#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DRIVER = ROOT / "testenv" / "scripts" / "vm-advance.py"


def main() -> int:
    text = DRIVER.read_text(encoding="utf-8")

    required = (
        'parser.add_argument("--cargo-home", type=Path, required=True)',
        'parser.add_argument("--protoc", type=Path, required=True)',
        'project / "upstream.lock.json"',
        'project / "testenv/scripts/run-static-gates.sh"',
        'project / "testenv/scripts/run-host-backend-gates.sh"',
        'project / "tests/test_core_integration.py"',
        'project / "testenv/scripts/run-qemu-host-sanity.sh"',
        'project / "testenv/scripts/run-armhf-gates.sh"',
        'project / "testenv/scripts/package-and-audit.sh"',
        'project / "testenv/scripts/run-qemu-smoke.sh"',
        '"hardware_acceptance": "not-run"',
        'len(unique_apkgs) < 5',
        '"non-hardware-release-gates-passed"',
        '"armhf-checkpoint-passed"',
        '"qemu-package-checkpoint-passed"',
        '"QEMU": str(qemu_exact)',
        '"BUILD_COMMIT": build_commit',
        'qemu_exact / "QEMU-PROVENANCE.txt"',
    )
    for needle in required:
        assert needle in text, f"vm-advance missing canonical contract: {needle}"

    # Exact-rootfs QEMU must execute before package construction. Missing private
    # rootfs bytes must return an ARMHF checkpoint without invoking packaging.
    qemu_gate = text.index('"qemu-exact-rootfs"')
    package_gate = text.index('"package-audit"')
    assert qemu_gate < package_gate, "vm-advance packages before exact-rootfs QEMU"

    no_rootfs = text.index("if not args.rootfs:")
    armhf_checkpoint = text.index('report["result"] = "armhf-checkpoint-passed"')
    assert no_rootfs < armhf_checkpoint < qemu_gate, (
        "vm-advance must terminate at an ARMHF checkpoint when rootfs is absent"
    )

    forbidden = (
        "kap_port::tests",
        '"software-build-gates-passed"',
        '"armhf-package-checkpoint-passed"',
        '("cargo-check",',
        '("cargo-test",',
        '("cargo-release",',
        '["cargo", "build"',
        '["cargo", "test"',
        '["cargo", "check"',
    )
    for needle in forbidden:
        assert needle not in text, f"vm-advance contains bypass/stale success path: {needle}"

    print("test_vm_advance_contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
