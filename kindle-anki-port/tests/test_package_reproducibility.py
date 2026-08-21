#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import os
import shutil
import subprocess
import tempfile
import zipfile
from pathlib import Path

SOURCE_ROOT = Path(os.environ.get("KAP_SOURCE_ROOT", Path(__file__).resolve().parents[1])).resolve()
PACKAGE_SCRIPT = SOURCE_ROOT / "testenv/scripts/package-and-audit.sh"
SOURCE_DATE_EPOCH = 1787340224
BUILD_COMMIT = "0123456789abcdef0123456789abcdef01234567"
EXECUTABLES = {
    "extensions/kindle-anki-port/kap-app",
    "extensions/kindle-anki-port/kap-audio",
    "extensions/kindle-anki-port/kap-sync",
    "extensions/kindle-anki-port/scripts/launch.sh",
    "extensions/kindle-anki-port/scripts/sync.sh",
    "documents/Kindle Anki.sh",
    "documents/Kindle Anki Sync.sh",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def make_project(root: Path) -> Path:
    project = root / "project"
    project.mkdir()
    for name in ("web", "scripts", "packaging"):
        shutil.copytree(SOURCE_ROOT / name, project / name, symlinks=True)
    for name in ("LICENSE", "upstream.lock.json"):
        shutil.copy2(SOURCE_ROOT / name, project / name)
    (project / "tools").mkdir()
    (project / "tests").mkdir()
    shutil.copy2(SOURCE_ROOT / "tools/audit_package.py", project / "tools/audit_package.py")
    shutil.copy2(SOURCE_ROOT / "tests/test_package_policy.py", project / "tests/test_package_policy.py")
    return project


def make_armhf(root: Path) -> Path:
    armhf = root / "armhf"
    armhf.mkdir()
    for name in ("kap-app", "kap-audio", "kap-sync", "libanki-kindle.so"):
        (armhf / name).write_bytes(("fixture:" + name + "\n").encode())
    for name in (
        "file.txt",
        "exports.txt",
        "ARMHF-GATES.txt",
        "BUILD-PROVENANCE.txt",
        "fixture.abi.txt",
        "fixture.glibc.txt",
    ):
        (armhf / name).write_text("fixture:" + name + "\n", encoding="utf-8")
    return armhf


def run_package(
    project: Path,
    armhf: Path,
    dist: Path,
    release: Path,
    *,
    tz: str,
    mask: int,
    epoch: int = SOURCE_DATE_EPOCH,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update(
        PROJECT=str(project),
        ARMHF=str(armhf),
        DIST=str(dist),
        RELEASE=str(release),
        VERSION="repro-test",
        BUILD_COMMIT=BUILD_COMMIT,
        SOURCE_DATE_EPOCH=str(epoch),
        TZ=tz,
    )
    return subprocess.run(
        ["bash", str(PACKAGE_SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
        preexec_fn=lambda: os.umask(mask),
        check=False,
    )


def assert_archive(archive: Path) -> None:
    expected_time = dt.datetime.fromtimestamp(
        SOURCE_DATE_EPOCH, tz=dt.timezone.utc
    ).timetuple()[:6]
    with zipfile.ZipFile(archive) as zf:
        if zf.testzip() is not None:
            raise AssertionError("archive CRC failure")
        names = zf.namelist()
        if names != sorted(names):
            raise AssertionError("archive members are not sorted deterministically")
        for info in zf.infolist():
            if info.date_time != expected_time:
                raise AssertionError(
                    f"non-canonical ZIP timestamp for {info.filename}: {info.date_time}"
                )
            mode = (info.external_attr >> 16) & 0o777
            expected_mode = 0o755 if info.filename in EXECUTABLES else 0o644
            if mode != expected_mode:
                raise AssertionError(
                    f"non-canonical ZIP mode for {info.filename}: "
                    f"{mode:o} != {expected_mode:o}"
                )


def main() -> int:
    if not PACKAGE_SCRIPT.is_file():
        raise SystemExit(f"missing package script: {PACKAGE_SCRIPT}")
    with tempfile.TemporaryDirectory(prefix="kap-package-repro-") as td:
        temp = Path(td)
        project = make_project(temp)
        armhf = make_armhf(temp)
        dist = temp / "dist"
        release = temp / "release"

        first = run_package(project, armhf, dist, release, tz="UTC", mask=0o022)
        if first.returncode != 0:
            raise AssertionError(first.stdout)
        archive = release / "Kindle-Anki-Port-PW6-armhf.zip"
        first_bytes = archive.read_bytes()
        first_hash = sha256(archive)
        assert_archive(archive)

        (release / "stale-sidecar.txt").write_text(
            "must disappear\n", encoding="utf-8"
        )
        second = run_package(project, armhf, dist, release, tz="UTC-9", mask=0o077)
        if second.returncode != 0:
            raise AssertionError(second.stdout)
        if (release / "stale-sidecar.txt").exists():
            raise AssertionError("release directory was not rebuilt from a clean state")
        if archive.read_bytes() != first_bytes:
            raise AssertionError(
                "package differs across timezone/umask: "
                f"{first_hash} != {sha256(archive)}"
            )
        assert_archive(archive)

        too_new = run_package(
            project,
            armhf,
            dist,
            release,
            tz="UTC",
            mask=0o022,
            epoch=4354819199,
        )
        if (
            too_new.returncode != 65
            or "exceeds the ZIP timestamp range" not in too_new.stdout
        ):
            raise AssertionError(
                "out-of-range SOURCE_DATE_EPOCH did not fail closed: "
                f"{too_new.returncode}\n{too_new.stdout}"
            )

        provenance = (release / "PACKAGE-PROVENANCE.txt").read_text(
            encoding="utf-8"
        )
        if f"source_date_epoch={SOURCE_DATE_EPOCH}\n" not in provenance:
            raise AssertionError("package provenance omitted SOURCE_DATE_EPOCH")
        if f"archive_sha256={first_hash}\n" not in provenance:
            raise AssertionError("package provenance omitted canonical archive hash")

        print(f"test_package_reproducibility: ok sha256={first_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
