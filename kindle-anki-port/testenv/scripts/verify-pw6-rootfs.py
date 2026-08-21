#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import re
import subprocess
from pathlib import Path


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def die(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Verify an extracted PW6 rootfs against the pinned runtime oracle")
    parser.add_argument("rootfs", type=Path)
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--rootfs-image", type=Path)
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[2]
    manifest_path = args.manifest or project / "testenv/qemu/pw6-5.19.6-rootfs-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    rootfs = args.rootfs.resolve()
    if not rootfs.is_dir():
        die(f"rootfs is not a directory: {rootfs}")

    if args.rootfs_image:
        expected = manifest["rootfs_image"]["sha256"]
        actual = sha256(args.rootfs_image)
        if actual != expected:
            die(f"rootfs image SHA-256 mismatch: expected {expected}, got {actual}")
        print(f"rootfs image sha256: PASS {actual}")

    for name, expected in manifest["runtime"]["files"].items():
        path = rootfs / name.lstrip("/")
        if not path.exists():
            die(f"required runtime file missing: {name}")
        actual = sha256(path)
        if actual != expected:
            die(f"SHA-256 mismatch for {name}: expected {expected}, got {actual}")
        print(f"{name}: PASS {actual}")

    pretty = rootfs / "etc/prettyversion.txt"
    version_txt = rootfs / "etc/version.txt"
    if not pretty.is_file() or manifest["firmware"]["version"] not in pretty.read_text(errors="replace"):
        die("prettyversion.txt does not identify the pinned firmware")
    version_body = version_txt.read_text(errors="replace") if version_txt.is_file() else ""
    if manifest["firmware"]["version_code"][:6] not in version_body:
        die("version.txt does not match the pinned firmware build family")

    libc = rootfs / "lib/libc.so.6"
    strings = subprocess.run(["strings", str(libc)], check=True, capture_output=True, text=True).stdout
    versions = []
    for match in re.findall(r"\bGLIBC_(\d+(?:\.\d+)+)\b", strings):
        versions.append(tuple(int(x) for x in match.split(".")))
    if not versions:
        die("no GLIBC symbol versions found in target libc")
    actual_max = ".".join(str(x) for x in max(versions))
    expected_max = manifest["runtime"]["glibc_max_symbol_version"]
    if actual_max != expected_max:
        die(f"target GLIBC ceiling mismatch: expected {expected_max}, got {actual_max}")
    print(f"target GLIBC ceiling: PASS GLIBC_{actual_max}")
    print("PW6 rootfs verification: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
