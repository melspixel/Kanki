#!/usr/bin/env python3
"""Prepare and verify a PW6 rootfs from a checksum-pinned firmware package.

Firmware/rootfs bytes are external test inputs. This tool verifies every pinned
hash, extracts into a private work directory, and never writes proprietary bytes
into the source tree.
"""
from __future__ import annotations

import argparse
import gzip
import hashlib
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


_CHUNK_SIZE = 1024 * 1024


def digest(path: Path, algorithm: str) -> str:
    hasher = hashlib.new(algorithm)
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(_CHUNK_SIZE), b""):
            hasher.update(chunk)
    return hasher.hexdigest()


def die(message: str) -> NoReturn:
    raise SystemExit(f"FAIL: {message}")


def require_executable(value: str | None, label: str) -> str:
    if not value:
        die(f"{label} executable was not provided and was not found on PATH")
    candidate = shutil.which(value) if os.sep not in value else value
    if not candidate or not Path(candidate).is_file() or not os.access(candidate, os.X_OK):
        die(f"{label} is not executable: {value}")
    return str(Path(candidate).resolve())


def require_empty_destination(destination: Path) -> None:
    if destination.exists():
        if not destination.is_dir():
            die(f"output path exists and is not a directory: {destination}")
        if any(destination.iterdir()):
            die(f"output directory is not empty: {destination}")
    else:
        destination.mkdir(parents=True)


def locate_rootfs_image(extracted: Path) -> Path:
    exact = sorted(extracted.rglob("rootfs.img.gz")) + sorted(extracted.rglob("rootfs.img"))
    candidates = exact or sorted(extracted.rglob("*rootfs*.img.gz")) or sorted(
        extracted.rglob("*rootfs*.img")
    )
    candidates = [candidate for candidate in candidates if candidate.is_file()]
    if len(candidates) != 1:
        names = ", ".join(str(path.relative_to(extracted)) for path in candidates) or "none"
        die(f"expected exactly one rootfs image after KindleTool extraction; found: {names}")
    return candidates[0]


def inflate_if_needed(source: Path, destination: Path) -> None:
    if source.suffix == ".gz":
        with gzip.open(source, "rb") as compressed, destination.open("wb") as output:
            shutil.copyfileobj(compressed, output, length=_CHUNK_SIZE)
    else:
        shutil.copyfile(source, destination)


def run_checked(command: list[str], *, env: dict[str, str] | None = None) -> None:
    print("+", " ".join(command), flush=True)
    subprocess.run(command, check=True, env=env)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Extract and verify the checksum-pinned Kindle PW6 5.19.6 rootfs"
    )
    parser.add_argument("firmware", type=Path, help="official PW6 firmware .bin")
    parser.add_argument("output", type=Path, help="empty destination for the extracted rootfs")
    parser.add_argument("--manifest", type=Path)
    parser.add_argument("--workdir", type=Path)
    parser.add_argument("--kindletool", default=os.environ.get("KINDLETOOL", "kindletool"))
    parser.add_argument("--debugfs", default=os.environ.get("DEBUGFS", "debugfs"))
    parser.add_argument("--verifier", type=Path)
    parser.add_argument("--keep-work", action="store_true")
    args = parser.parse_args()

    project = Path(__file__).resolve().parents[2]
    manifest_path = args.manifest or project / "testenv/qemu/pw6-5.19.6-rootfs-manifest.json"
    verifier = args.verifier or project / "testenv/scripts/verify-pw6-rootfs.py"
    firmware = args.firmware.resolve()
    output = args.output.resolve()
    workdir = (args.workdir or output.parent / ".pw6-rootfs-work").resolve()

    if not firmware.is_file():
        die(f"firmware file does not exist: {firmware}")
    if not manifest_path.is_file():
        die(f"manifest does not exist: {manifest_path}")
    if not verifier.is_file():
        die(f"rootfs verifier does not exist: {verifier}")

    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    firmware_meta = manifest.get("firmware", {})
    rootfs_meta = manifest.get("rootfs_image", {})
    expected_firmware_sha = firmware_meta.get("sha256")
    expected_firmware_md5 = firmware_meta.get("md5")
    expected_rootfs_sha = rootfs_meta.get("sha256")
    if not all((expected_firmware_sha, expected_firmware_md5, expected_rootfs_sha)):
        die("manifest is missing firmware SHA-256/MD5 or rootfs SHA-256")

    actual_firmware_sha = digest(firmware, "sha256")
    if actual_firmware_sha != expected_firmware_sha:
        die(
            "firmware SHA-256 mismatch: "
            f"expected {expected_firmware_sha}, got {actual_firmware_sha}"
        )
    actual_firmware_md5 = digest(firmware, "md5")
    if actual_firmware_md5 != expected_firmware_md5:
        die(f"firmware MD5 mismatch: expected {expected_firmware_md5}, got {actual_firmware_md5}")
    print(f"firmware sha256: PASS {actual_firmware_sha}")
    print(f"firmware md5: PASS {actual_firmware_md5}")

    kindletool = require_executable(args.kindletool, "KindleTool")
    debugfs = require_executable(args.debugfs, "debugfs")
    require_empty_destination(output)

    if workdir == output or output in workdir.parents:
        die("work directory must not be inside the output rootfs")
    if workdir.exists():
        shutil.rmtree(workdir)
    extracted = workdir / "firmware"
    extracted.mkdir(parents=True)
    image = workdir / "rootfs.img"

    try:
        run_checked([kindletool, "extract", str(firmware), str(extracted)])
        archived_image = locate_rootfs_image(extracted)
        inflate_if_needed(archived_image, image)

        actual_rootfs_sha = digest(image, "sha256")
        if actual_rootfs_sha != expected_rootfs_sha:
            die(
                "rootfs image SHA-256 mismatch: "
                f"expected {expected_rootfs_sha}, got {actual_rootfs_sha}"
            )
        print(f"rootfs image sha256: PASS {actual_rootfs_sha}")

        # debugfs's rdump preserves the rootfs hierarchy without requiring a
        # privileged mount. The destination is guaranteed empty above.
        run_checked([debugfs, "-R", f"rdump / {output}", str(image)])
        run_checked(
            [
                sys.executable,
                str(verifier.resolve()),
                str(output),
                "--manifest",
                str(manifest_path.resolve()),
                "--rootfs-image",
                str(image),
            ]
        )

        provenance = {
            "schema": 1,
            "manifest": str(manifest_path.resolve()),
            "firmware": {
                "path": str(firmware),
                "sha256": actual_firmware_sha,
                "md5": actual_firmware_md5,
            },
            "rootfs_image": {
                "sha256": actual_rootfs_sha,
                "extracted_member": str(archived_image.relative_to(extracted)),
            },
            "output": str(output),
            "tools": {
                "kindletool": kindletool,
                "debugfs": debugfs,
                "python": sys.executable,
            },
        }
        provenance_path = output.parent / f"{output.name}.provenance.json"
        provenance_path.write_text(json.dumps(provenance, indent=2, sort_keys=True) + "\n")
        print(f"PW6 rootfs prepared: PASS {output}")
        print(f"provenance: {provenance_path}")
    except SystemExit:
        shutil.rmtree(output, ignore_errors=True)
        raise
    except (OSError, subprocess.CalledProcessError, gzip.BadGzipFile) as error:
        shutil.rmtree(output, ignore_errors=True)
        die(str(error))
    finally:
        if not args.keep_work:
            shutil.rmtree(workdir, ignore_errors=True)

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
