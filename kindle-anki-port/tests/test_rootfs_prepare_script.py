#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "testenv" / "scripts" / "prepare-pw6-rootfs.sh"


def run_script(*args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(SCRIPT), *args],
        text=True,
        capture_output=True,
    )


class RootfsPreparationScriptTests(unittest.TestCase):
    def test_shell_syntax_and_pinned_sources(self) -> None:
        subprocess.run(["sh", "-n", str(SCRIPT)], check=True)
        result = run_script("--print-sources")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("update_KindlePaperwhite_12th_Gen_2024", result.stdout)
        self.assertIn("update_kindle_all_new_paperwhite_12th_5.19.6.bin", result.stdout)
        self.assertNotIn("Community mirror", result.stdout)
        self.assertIn(
            "72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c",
            result.stdout,
        )
        self.assertIn("697aeb33c02f46b9b0911ab05c28b06d", result.stdout)
        self.assertIn(
            "b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa",
            result.stdout,
        )

    def test_bad_firmware_is_rejected_before_external_tools(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kap-rootfs-") as temp:
            root = Path(temp)
            firmware = root / "bad.bin"
            firmware.write_bytes(b"not a Kindle update")
            result = run_script(
                "--firmware",
                str(firmware),
                "--output",
                str(root / "rootfs"),
                "--kindletool",
                str(root / "missing-kindletool"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("firmware SHA-256 mismatch", result.stderr)
            self.assertNotIn("KindleTool not found", result.stderr)

    def test_md5_is_verified_before_external_tools(self) -> None:
        with tempfile.TemporaryDirectory(prefix="kap-rootfs-md5-") as temp:
            root = Path(temp)
            firmware = root / "fixture.bin"
            payload = b"synthetic firmware fixture"
            firmware.write_bytes(payload)
            manifest = root / "manifest.json"
            manifest.write_text(
                json.dumps(
                    {
                        "firmware": {
                            "sha256": hashlib.sha256(payload).hexdigest(),
                            "md5": "0" * 32,
                        },
                        "rootfs_image": {"sha256": "1" * 64},
                    }
                ),
                encoding="utf-8",
            )
            result = run_script(
                "--manifest",
                str(manifest),
                "--firmware",
                str(firmware),
                "--output",
                str(root / "rootfs"),
                "--kindletool",
                str(root / "missing-kindletool"),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("firmware MD5 mismatch", result.stderr)
            self.assertNotIn("KindleTool not found", result.stderr)


if __name__ == "__main__":
    unittest.main()
