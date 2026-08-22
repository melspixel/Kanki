#!/usr/bin/env python3
from datetime import datetime, timezone
from pathlib import Path
import os
import stat
import subprocess
import sys
import tempfile
from zipfile import ZipFile


ROOT = Path(__file__).resolve().parents[1]
RECIPE = ROOT / "tools" / "create_reproducible_zip.py"
EPOCH = 1_700_000_000


def fixture(root: Path, reverse: bool) -> None:
    entries = [
        ("z.txt", b"stable text\n", 0o644),
        ("bin/run.sh", b"#!/bin/sh\nexit 0\n", 0o755),
    ]
    if reverse:
        entries.reverse()
    for index, (relative, content, mode) in enumerate(entries):
        path = root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
        path.chmod(mode)
        os.utime(path, (EPOCH + 500 + index, EPOCH + 500 + index))


with tempfile.TemporaryDirectory(prefix="kanki-reproducible-zip-") as temporary:
    temporary_root = Path(temporary)
    first_root = temporary_root / "first"
    second_root = temporary_root / "second"
    fixture(first_root, reverse=False)
    fixture(second_root, reverse=True)
    first_zip = temporary_root / "first.zip"
    second_zip = temporary_root / "second.zip"
    for package_root, output in [(first_root, first_zip), (second_root, second_zip)]:
        subprocess.run(
            [sys.executable, str(RECIPE), str(package_root), str(output), str(EPOCH)],
            check=True,
            capture_output=True,
            text=True,
        )

    assert first_zip.read_bytes() == second_zip.read_bytes(), (
        "archive must ignore source creation order and file mtimes"
    )
    expected_time = datetime.fromtimestamp(EPOCH, timezone.utc)
    expected_tuple = (
        expected_time.year,
        expected_time.month,
        expected_time.day,
        expected_time.hour,
        expected_time.minute,
        expected_time.second,
    )
    with ZipFile(first_zip) as archive:
        assert archive.namelist() == ["bin/run.sh", "z.txt"]
        assert all(info.date_time == expected_tuple for info in archive.infolist())
        modes = {
            info.filename: stat.S_IMODE(info.external_attr >> 16)
            for info in archive.infolist()
        }
        assert modes == {"bin/run.sh": 0o755, "z.txt": 0o644}
        assert archive.read("z.txt") == b"stable text\n"

print("reproducible zip contract: pass sorted=true epoch=fixed modes=fixed")
