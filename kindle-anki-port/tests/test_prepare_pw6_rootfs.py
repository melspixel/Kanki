#!/usr/bin/env python3
from __future__ import annotations

import gzip
import hashlib
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path


def digest(path: Path, algorithm: str) -> str:
    h = hashlib.new(algorithm)
    h.update(path.read_bytes())
    return h.hexdigest()


def write_executable(path: Path, body: str) -> None:
    path.write_text(body, encoding="utf-8")
    path.chmod(0o755)


def run(command: list[str], env: dict[str, str], expected: int = 0) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(command, env=env, text=True, capture_output=True)
    if result.returncode != expected:
        raise AssertionError(
            f"expected status {expected}, got {result.returncode}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def main() -> int:
    script = Path(__file__).resolve().parents[1] / "testenv/scripts/prepare-pw6-rootfs.py"
    verifier = Path(__file__).resolve().parents[1] / "testenv/scripts/verify-pw6-rootfs.py"
    with tempfile.TemporaryDirectory(prefix="kap-prepare-rootfs-") as tmp_text:
        tmp = Path(tmp_text)
        firmware = tmp / "firmware.bin"
        firmware.write_bytes(b"synthetic-pw6-firmware\n")
        rootfs_image = tmp / "fixture-rootfs.img"
        rootfs_image.write_bytes(b"synthetic-rootfs-image\n")
        rootfs_archive = tmp / "rootfs.img.gz"
        with gzip.open(rootfs_archive, "wb") as stream:
            stream.write(rootfs_image.read_bytes())

        fixture_root = tmp / "fixture-root"
        files = {
            "lib/ld-linux-armhf.so.3": b"fake loader\nGLIBC_2.4\nGLIBC_2.35\n",
            "lib/libc.so.6": b"fake libc\nGLIBC_2.4\nGLIBC_2.35\n",
            "usr/lib/libwebkitgtk-1.0.so.0.7.2": b"fake webkit\n",
        }
        for relative, data in files.items():
            path = fixture_root / relative
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(data)
        (fixture_root / "etc").mkdir(parents=True)
        (fixture_root / "etc/prettyversion.txt").write_text("Kindle 5.19.6\n")
        (fixture_root / "etc/version.txt").write_text("System Software Version: 483216 test\n")

        manifest = {
            "schema": 1,
            "firmware": {
                "version": "5.19.6",
                "version_code": "4832160042",
                "sha256": digest(firmware, "sha256"),
                "md5": digest(firmware, "md5"),
            },
            "rootfs_image": {"sha256": digest(rootfs_image, "sha256")},
            "runtime": {
                "glibc_max_symbol_version": "2.35",
                "files": {
                    f"/{name}": hashlib.sha256(data).hexdigest() for name, data in files.items()
                },
            },
        }
        manifest_path = tmp / "manifest.json"
        manifest_path.write_text(json.dumps(manifest))

        fake_kindletool = tmp / "kindletool"
        write_executable(
            fake_kindletool,
            """#!/usr/bin/env python3
import os, pathlib, shutil, sys
if len(sys.argv) != 4 or sys.argv[1] != 'extract':
    raise SystemExit(64)
out = pathlib.Path(sys.argv[3])
out.mkdir(parents=True, exist_ok=True)
shutil.copyfile(os.environ['KAP_FAKE_ROOTFS_ARCHIVE'], out / 'rootfs.img.gz')
""",
        )
        fake_debugfs = tmp / "debugfs"
        write_executable(
            fake_debugfs,
            """#!/usr/bin/env python3
import os, pathlib, shlex, shutil, sys
if len(sys.argv) != 4 or sys.argv[1] != '-R':
    raise SystemExit(64)
parts = shlex.split(sys.argv[2])
if parts[:2] != ['rdump', '/'] or len(parts) != 3:
    raise SystemExit(65)
dst = pathlib.Path(parts[2])
src = pathlib.Path(os.environ['KAP_FAKE_ROOTFS_DIR'])
for item in src.rglob('*'):
    target = dst / item.relative_to(src)
    if item.is_dir():
        target.mkdir(parents=True, exist_ok=True)
    elif item.is_symlink():
        target.parent.mkdir(parents=True, exist_ok=True)
        target.symlink_to(os.readlink(item))
    else:
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(item, target)
""",
        )

        env = os.environ.copy()
        env["KAP_FAKE_ROOTFS_ARCHIVE"] = str(rootfs_archive)
        env["KAP_FAKE_ROOTFS_DIR"] = str(fixture_root)
        output = tmp / "prepared-rootfs"
        command = [
            sys.executable,
            str(script),
            str(firmware),
            str(output),
            "--manifest",
            str(manifest_path),
            "--kindletool",
            str(fake_kindletool),
            "--debugfs",
            str(fake_debugfs),
            "--verifier",
            str(verifier),
        ]
        success = run(command, env)
        assert "PW6 rootfs prepared: PASS" in success.stdout
        assert (output / "lib/libc.so.6").read_bytes() == files["lib/libc.so.6"]
        provenance = json.loads((tmp / "prepared-rootfs.provenance.json").read_text())
        assert provenance["firmware"]["sha256"] == manifest["firmware"]["sha256"]
        assert provenance["rootfs_image"]["sha256"] == manifest["rootfs_image"]["sha256"]

        # The tool refuses to overwrite an existing extracted rootfs.
        nonempty = run(command, env, expected=1)
        assert "output directory is not empty" in nonempty.stderr

        # Firmware identity is checked before either extraction executable runs.
        bad_firmware = tmp / "wrong.bin"
        bad_firmware.write_bytes(b"wrong\n")
        mismatch_command = command.copy()
        mismatch_command[2] = str(bad_firmware)
        mismatch = run(mismatch_command, env, expected=1)
        assert "firmware SHA-256 mismatch" in mismatch.stderr

        # A tampered extracted image is rejected and the partial output is removed.
        tampered_archive = tmp / "tampered.img.gz"
        with gzip.open(tampered_archive, "wb") as stream:
            stream.write(b"tampered-rootfs-image\n")
        tampered_output = tmp / "tampered-output"
        tampered_command = command.copy()
        tampered_command[3] = str(tampered_output)
        tampered_env = env.copy()
        tampered_env["KAP_FAKE_ROOTFS_ARCHIVE"] = str(tampered_archive)
        mismatch = run(tampered_command, tampered_env, expected=1)
        assert "rootfs image SHA-256 mismatch" in mismatch.stderr
        assert not tampered_output.exists()

    print("test_prepare_pw6_rootfs: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
