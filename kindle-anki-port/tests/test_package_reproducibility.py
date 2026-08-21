#!/usr/bin/env python3
from __future__ import annotations

import datetime as dt
import hashlib
import json
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
ANKI_COMMIT = json.loads((SOURCE_ROOT / "upstream.lock.json").read_text(encoding="utf-8"))["commit"]
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
    (project / "testenv" / "qemu").mkdir(parents=True)
    shutil.copy2(SOURCE_ROOT / "tools/audit_package.py", project / "tools/audit_package.py")
    shutil.copy2(SOURCE_ROOT / "tests/test_package_policy.py", project / "tests/test_package_policy.py")
    shutil.copy2(
        SOURCE_ROOT / "testenv/qemu/pw6-5.19.6-rootfs-manifest.json",
        project / "testenv/qemu/pw6-5.19.6-rootfs-manifest.json",
    )
    return project


def write_armhf_provenance(
    armhf: Path,
    *,
    source_commit: str = BUILD_COMMIT,
    anki_commit: str = ANKI_COMMIT,
) -> None:
    (armhf / "BUILD-PROVENANCE.txt").write_text(
        f"source_commit={source_commit}\nanki_commit={anki_commit}\n",
        encoding="utf-8",
    )


def make_armhf(root: Path) -> Path:
    armhf = root / "armhf"
    armhf.mkdir()
    for name in ("kap-app", "kap-audio", "kap-sync", "libanki-kindle.so"):
        (armhf / name).write_bytes(("fixture:" + name + "\n").encode())
    for name in ("file.txt", "exports.txt", "fixture.abi.txt", "fixture.glibc.txt"):
        (armhf / name).write_text("fixture:" + name + "\n", encoding="utf-8")
    (armhf / "ARMHF-GATES.txt").write_text("ARMHF gates: PASS\n", encoding="utf-8")
    write_armhf_provenance(armhf)
    return armhf


def write_qemu_provenance(
    qemu: Path,
    armhf: Path,
    project: Path,
    *,
    source_commit: str = BUILD_COMMIT,
    anki_commit: str = ANKI_COMMIT,
    binary_hash_overrides: dict[str, str] | None = None,
) -> None:
    overrides = binary_hash_overrides or {}
    manifest = project / "testenv/qemu/pw6-5.19.6-rootfs-manifest.json"
    lines = [
        "qemu-arm fixture 1.0",
        f"source_commit={source_commit}",
        f"anki_commit={anki_commit}",
        "rootfs_manifest_id=pw6-5.19.6-rootfs-manifest.json",
        f"rootfs_manifest_sha256={sha256(manifest)}",
        "rootfs_verified=true",
    ]
    for name in ("libanki-kindle.so", "kap-app", "kap-audio", "kap-sync"):
        lines.append(f"{name}_sha256={overrides.get(name, sha256(armhf / name))}")
    (qemu / "QEMU-PROVENANCE.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")


def make_qemu(root: Path, armhf: Path, project: Path) -> Path:
    qemu = root / "qemu"
    qemu.mkdir()
    (qemu / "QEMU-SMOKE.txt").write_text("QEMU smoke: PASS\n", encoding="utf-8")
    (qemu / "rootfs-verification.txt").write_text(
        "PW6 rootfs verification: PASS\n", encoding="utf-8"
    )
    (qemu / "backend-smoke.txt").write_text("qemu backend smoke: ok\n", encoding="utf-8")
    (qemu / "audio-self-test.txt").write_text("kap-audio self-test: ok\n", encoding="utf-8")
    (qemu / "sync-self-test.txt").write_text("kap-sync self-test: ok\n", encoding="utf-8")
    write_qemu_provenance(qemu, armhf, project)
    return qemu


def run_package(
    project: Path,
    armhf: Path,
    qemu: Path,
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
        QEMU=str(qemu),
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


def assert_provenance_rejected(
    result: subprocess.CompletedProcess[str], expected_message: str
) -> None:
    if result.returncode != 66 or expected_message not in result.stdout:
        raise AssertionError(
            "release provenance did not fail closed: "
            f"{result.returncode}\n{result.stdout}"
        )


def main() -> int:
    if not PACKAGE_SCRIPT.is_file():
        raise SystemExit(f"missing package script: {PACKAGE_SCRIPT}")
    with tempfile.TemporaryDirectory(prefix="kap-package-repro-") as td:
        temp = Path(td)
        project = make_project(temp)
        armhf = make_armhf(temp)
        qemu = make_qemu(temp, armhf, project)
        dist = temp / "dist"
        release = temp / "release"

        first = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        if first.returncode != 0:
            raise AssertionError(first.stdout)
        archive = release / "Kindle-Anki-Port-PW6-armhf.zip"
        first_bytes = archive.read_bytes()
        first_hash = sha256(archive)
        assert_archive(archive)
        for evidence in (
            "QEMU-SMOKE.txt",
            "QEMU-PROVENANCE.txt",
            "rootfs-verification.txt",
            "backend-smoke.txt",
            "audio-self-test.txt",
            "sync-self-test.txt",
        ):
            if not (release / evidence).is_file():
                raise AssertionError(f"release omitted QEMU evidence: {evidence}")

        (release / "stale-sidecar.txt").write_text(
            "must disappear\n", encoding="utf-8"
        )
        second = run_package(project, armhf, qemu, dist, release, tz="UTC-9", mask=0o077)
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

        write_armhf_provenance(armhf, source_commit="f" * 40)
        wrong_source = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(wrong_source, "ARMHF source_commit mismatch")

        write_armhf_provenance(armhf, anki_commit="e" * 40)
        wrong_anki = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(wrong_anki, "ARMHF anki_commit mismatch")
        write_armhf_provenance(armhf)

        write_qemu_provenance(qemu, armhf, project, source_commit="d" * 40)
        wrong_qemu_source = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(wrong_qemu_source, "QEMU source_commit mismatch")

        write_qemu_provenance(qemu, armhf, project, anki_commit="c" * 40)
        wrong_qemu_anki = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(wrong_qemu_anki, "QEMU anki_commit mismatch")

        write_qemu_provenance(
            qemu,
            armhf,
            project,
            binary_hash_overrides={"kap-app": "b" * 64},
        )
        wrong_qemu_hash = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(wrong_qemu_hash, "QEMU artifact hash mismatch for kap-app")
        write_qemu_provenance(qemu, armhf, project)

        (qemu / "QEMU-SMOKE.txt").write_text("QEMU smoke: FAIL\n", encoding="utf-8")
        failed_qemu = run_package(project, armhf, qemu, dist, release, tz="UTC", mask=0o022)
        assert_provenance_rejected(failed_qemu, "QEMU-SMOKE.txt does not record PASS")
        (qemu / "QEMU-SMOKE.txt").write_text("QEMU smoke: PASS\n", encoding="utf-8")

        too_new = run_package(
            project,
            armhf,
            qemu,
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
        if f"rootfs_manifest_sha256={sha256(project / 'testenv/qemu/pw6-5.19.6-rootfs-manifest.json')}\n" not in provenance:
            raise AssertionError("package provenance omitted rootfs manifest hash")
        if "qemu_provenance_sha256=" not in provenance:
            raise AssertionError("package provenance omitted QEMU provenance hash")

        print(f"test_package_reproducibility: ok sha256={first_hash}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
