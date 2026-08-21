#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDITOR = ROOT / "tools/audit_package.py"
REQUIRED = [
    "extensions/kindle-anki-port/kap-app",
    "extensions/kindle-anki-port/kap-audio",
    "extensions/kindle-anki-port/kap-sync",
    "extensions/kindle-anki-port/libanki-kindle.so",
    "extensions/kindle-anki-port/scripts/launch.sh",
    "extensions/kindle-anki-port/scripts/sync.sh",
    "documents/Kindle Anki.sh",
    "documents/Kindle Anki Sync.sh",
]


def make_package(path: Path, extra: dict[str, str] | None = None) -> None:
    with zipfile.ZipFile(path, "w") as archive:
        for name in REQUIRED:
            archive.writestr(name, "#!/bin/sh\nexit 0\n" if name.endswith(".sh") else "binary")
        for name, text in (extra or {}).items():
            archive.writestr(name, text)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kap-package-test-") as tmp_text:
        tmp = Path(tmp_text)
        good = tmp / "good.zip"
        make_package(good)
        subprocess.run(["python3", str(AUDITOR), str(good)], check=True)

        bad = tmp / "bad.zip"
        make_package(bad, {"extensions/kindle-anki-port/config.ini": "hkey=secret\n"})
        result = subprocess.run(["python3", str(AUDITOR), str(bad)], text=True, capture_output=True)
        assert result.returncode != 0
        assert "forbidden user/runtime file" in result.stdout

        traversal = tmp / "traversal.zip"
        make_package(traversal, {"../escape.txt": "bad"})
        result = subprocess.run(["python3", str(AUDITOR), str(traversal)], text=True, capture_output=True)
        assert result.returncode != 0
        assert "unsafe path" in result.stdout

        secret = tmp / "secret.zip"
        make_package(secret, {"extensions/kindle-anki-port/config.example.ini": "hkey=REAL_SECRET\n"})
        result = subprocess.run(["python3", str(AUDITOR), str(secret)], text=True, capture_output=True)
        assert result.returncode != 0
        assert "sync credential" in result.stdout

    print("test_package_audit: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
