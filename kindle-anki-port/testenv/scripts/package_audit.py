#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CANONICAL_AUDITOR = ROOT / "tools" / "audit_package.py"
PACKAGE_POLICY = ROOT / "tests" / "test_package_policy.py"


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compatibility front-end for the canonical fail-closed package gates."
    )
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--sha256-out", type=Path)
    args = parser.parse_args()

    if not args.package.is_file():
        raise SystemExit(f"package does not exist: {args.package}")

    audit = [sys.executable, str(CANONICAL_AUDITOR), str(args.package)]
    if args.sha256_out:
        audit.extend(["--sha256-out", str(args.sha256_out)])
    result = subprocess.run(audit, check=False)
    if result.returncode:
        return result.returncode

    result = subprocess.run(
        [sys.executable, str(PACKAGE_POLICY), str(args.package)], check=False
    )
    if result.returncode:
        return result.returncode

    report = {
        "schema": 1,
        "package": args.package.name,
        "sha256": hashlib.sha256(args.package.read_bytes()).hexdigest(),
        "result": "pass",
        "auditor": str(CANONICAL_AUDITOR.relative_to(ROOT)),
        "policy": str(PACKAGE_POLICY.relative_to(ROOT)),
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
