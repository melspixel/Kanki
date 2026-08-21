#!/usr/bin/env python3
"""Run one durable VM-side Kindle Anki checkpoint through canonical gates.

The driver deliberately delegates build semantics to the maintained gate scripts. It
never substitutes a narrow cargo test for the official-backend gate, never packages
before exact-rootfs QEMU has passed for the exact ARMHF bytes, and never marks
physical PW6 acceptance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import time
from pathlib import Path
from typing import Any


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git_head(path: Path) -> str:
    return subprocess.check_output(
        ["git", "-C", str(path), "rev-parse", "HEAD"], text=True
    ).strip()


def write_report(path: Path, report: dict[str, Any]) -> None:
    report["updated_utc_epoch"] = time.time()
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run(
    name: str,
    command: list[str],
    *,
    cwd: Path,
    env: dict[str, str],
    logdir: Path,
    timeout: int,
) -> dict[str, Any]:
    started = time.time()
    log_path = logdir / f"{name}.log"
    try:
        proc = subprocess.run(
            command,
            cwd=cwd,
            env={**os.environ, **env},
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
        )
        output = proc.stdout
        returncode = proc.returncode
        timed_out = False
    except subprocess.TimeoutExpired as error:
        output = error.stdout or ""
        if isinstance(output, bytes):
            output = output.decode("utf-8", "replace")
        output += f"\nTIMEOUT after {timeout}s\n"
        returncode = 124
        timed_out = True
    log_path.write_text(output, encoding="utf-8", errors="replace")
    return {
        "name": name,
        "command": command,
        "cwd": str(cwd),
        "returncode": returncode,
        "seconds": round(time.time() - started, 3),
        "timed_out": timed_out,
        "log": str(log_path),
        "log_sha256": sha256(log_path),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--anki", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--cargo-home", type=Path, required=True)
    parser.add_argument("--protoc", type=Path, required=True)
    parser.add_argument("--kindle-toolchain-bin", type=Path)
    parser.add_argument("--qemu-arm", default="qemu-arm-static")
    parser.add_argument("--rootfs", type=Path)
    parser.add_argument("--rootfs-image", type=Path)
    parser.add_argument("--apkg", type=Path, action="append", default=[])
    parser.add_argument("--typed-apkg", type=Path)
    args = parser.parse_args()

    project = args.project.resolve()
    source = args.anki.resolve()
    work = args.work.resolve()
    cargo_home = args.cargo_home.resolve()
    protoc = args.protoc.resolve()
    checkout = work / "anki"
    logs = work / "logs"
    report_path = work / "report.json"
    armhf = work / "armhf"
    qemu_exact = work / "qemu-exact-rootfs"
    release = work / "release"
    logs.mkdir(parents=True, exist_ok=True)

    if not project.is_dir() or not source.is_dir():
        raise SystemExit("--project and --anki must be directories")
    if not cargo_home.is_dir():
        raise SystemExit("--cargo-home must name a prepared offline Cargo cache")
    if not protoc.is_file():
        raise SystemExit("--protoc must name the pinned protoc executable")
    if args.rootfs and not args.kindle_toolchain_bin:
        raise SystemExit("--rootfs requires --kindle-toolchain-bin")
    if args.rootfs_image and not args.rootfs:
        raise SystemExit("--rootfs-image requires --rootfs")

    lock = json.loads((project / "upstream.lock.json").read_text(encoding="utf-8"))
    expected_anki = str(lock["commit"])
    source_head = git_head(source)
    build_commit = git_head(project)

    report: dict[str, Any] = {
        "schema": 3,
        "started_utc_epoch": time.time(),
        "project": str(project),
        "build_commit": build_commit,
        "anki_source": str(source),
        "anki_expected_commit": expected_anki,
        "anki_source_commit": source_head,
        "steps": [],
        "artifacts": {},
        "inputs": {},
        "hardware_acceptance": "not-run",
        "result": "running",
    }
    write_report(report_path, report)
    if source_head != expected_anki:
        report["result"] = "failed-upstream-pin"
        write_report(report_path, report)
        print(f"Anki source pin mismatch: expected {expected_anki}, got {source_head}")
        return 2

    if checkout.exists():
        shutil.rmtree(checkout)
    shutil.copytree(source, checkout, symlinks=True)

    common_env = {
        "CARGO_HOME": str(cargo_home),
        "PROTOC": str(protoc),
        "CARGO_TERM_COLOR": "never",
    }

    def gate(name: str, command: list[str], env: dict[str, str], timeout: int) -> bool:
        step = run(name, command, cwd=project, env=env, logdir=logs, timeout=timeout)
        report["steps"].append(step)
        if step["returncode"] != 0:
            report["result"] = f"failed-{name}"
            write_report(report_path, report)
            return False
        write_report(report_path, report)
        return True

    if not gate(
        "static-gates",
        ["sh", str(project / "testenv/scripts/run-static-gates.sh")],
        {"KAP_BUILD_DIR": str(work / "static-gates")},
        1800,
    ):
        return 1

    if not gate(
        "host-backend-gates",
        ["bash", str(project / "testenv/scripts/run-host-backend-gates.sh")],
        {
            **common_env,
            "PROJECT": str(project),
            "ANKI": str(checkout),
        },
        10800,
    ):
        return 1

    host_library = checkout / "target/release/libanki.so"
    if not host_library.is_file():
        report["result"] = "failed-missing-host-libanki"
        write_report(report_path, report)
        return 1
    report["artifacts"]["host_libanki_sha256"] = sha256(host_library)

    apkg_paths = [path.resolve() for path in args.apkg]
    typed_apkg = args.typed_apkg.resolve() if args.typed_apkg else None
    for path in [*apkg_paths, *([typed_apkg] if typed_apkg else [])]:
        if not path.is_file():
            raise SystemExit(f"APKG input does not exist: {path}")
    unique_apkgs = {str(path) for path in apkg_paths}
    if typed_apkg:
        unique_apkgs.add(str(typed_apkg))
    report["inputs"]["apkg"] = [
        {"path": str(path), "sha256": sha256(path)} for path in sorted({Path(p) for p in unique_apkgs})
    ]
    report["inputs"]["typed_apkg"] = str(typed_apkg) if typed_apkg else None

    if apkg_paths or typed_apkg:
        command = [
            "python3",
            str(project / "tests/test_core_integration.py"),
            "--library",
            str(host_library),
        ]
        for path in apkg_paths:
            command.extend(["--apkg", str(path)])
        if typed_apkg:
            command.extend(["--typed-apkg", str(typed_apkg)])
        if not apkg_paths and typed_apkg:
            command.extend(["--apkg", str(typed_apkg)])
        if not gate("real-apkg-integration", command, {}, 3600):
            return 1

    if not args.kindle_toolchain_bin:
        report["result"] = "host-checkpoint-passed"
        report["release_gate_missing"] = [
            "KindleHF toolchain / ARMHF ABI build",
            "five-real-APKG integration" if len(unique_apkgs) < 5 else None,
            "typed-APKG integration" if not typed_apkg else None,
            "exact-rootfs QEMU smoke",
            "final package",
        ]
        report["release_gate_missing"] = [item for item in report["release_gate_missing"] if item]
        write_report(report_path, report)
        return 0

    bindir = args.kindle_toolchain_bin.resolve()
    if not (bindir / "arm-kindlehf-linux-gnueabihf-gcc").is_file():
        raise SystemExit("KindleHF compiler is missing from --kindle-toolchain-bin")

    tool_env = {
        **common_env,
        "PROJECT": str(project),
        "ANKI": str(checkout),
        "TOOLCHAIN_BIN": str(bindir),
        "QEMU_ARM": args.qemu_arm,
    }
    if not gate(
        "qemu-host-sanity",
        ["bash", str(project / "testenv/scripts/run-qemu-host-sanity.sh")],
        {**tool_env, "OUT": str(work / "qemu-host-sanity")},
        900,
    ):
        return 1

    if not gate(
        "armhf-gates",
        ["bash", str(project / "testenv/scripts/run-armhf-gates.sh")],
        {**tool_env, "OUT": str(armhf), "BUILD_COMMIT": build_commit},
        14400,
    ):
        return 1

    for name in ("kap-app", "kap-audio", "kap-sync", "libanki-kindle.so"):
        path = armhf / name
        if path.is_file():
            report["artifacts"][f"armhf/{name}"] = sha256(path)

    missing: list[str] = []
    if len(unique_apkgs) < 5:
        missing.append("five-real-APKG integration")
    if not typed_apkg:
        missing.append("typed-APKG integration")
    if not args.rootfs:
        missing.append("exact-rootfs QEMU smoke")
        missing.append("final package")

    # Final packaging is intentionally impossible until exact-rootfs QEMU has
    # passed for the exact ARMHF bytes. If the private rootfs is absent, stop at
    # a durable ARMHF checkpoint rather than constructing a final-looking ZIP.
    if not args.rootfs:
        report["result"] = "armhf-checkpoint-passed"
        report["release_gate_missing"] = missing
        report["completed_utc_epoch"] = time.time()
        write_report(report_path, report)
        return 0

    rootfs = args.rootfs.resolve()
    qemu_env = {
        "PROJECT": str(project),
        "ARMHF": str(armhf),
        "ROOTFS": str(rootfs),
        "TOOLCHAIN_BIN": str(bindir),
        "QEMU_ARM": args.qemu_arm,
        "OUT": str(qemu_exact),
        "BUILD_COMMIT": build_commit,
    }
    if args.rootfs_image:
        qemu_env["ROOTFS_IMAGE"] = str(args.rootfs_image.resolve())
    if not gate(
        "qemu-exact-rootfs",
        ["bash", str(project / "testenv/scripts/run-qemu-smoke.sh")],
        qemu_env,
        1800,
    ):
        return 1

    report["artifacts"]["qemu_provenance_sha256"] = sha256(
        qemu_exact / "QEMU-PROVENANCE.txt"
    )

    # A package can be produced only after the exact-rootfs gate above. The
    # package script independently rechecks the QEMU source/Anki/manifest/binary
    # hashes, so stale evidence cannot be relabelled by this orchestration layer.
    if not gate(
        "package-audit",
        ["bash", str(project / "testenv/scripts/package-and-audit.sh")],
        {
            "PROJECT": str(project),
            "ARMHF": str(armhf),
            "QEMU": str(qemu_exact),
            "RELEASE": str(release),
            "BUILD_COMMIT": build_commit,
            "VERSION": "0.1.0-dev",
        },
        1800,
    ):
        return 1

    if release.is_dir():
        report["artifacts"]["release"] = {
            str(path.relative_to(release)): {"sha256": sha256(path), "bytes": path.stat().st_size}
            for path in sorted(release.rglob("*"))
            if path.is_file()
        }

    if len(unique_apkgs) < 5:
        missing.append("five-real-APKG integration") if "five-real-APKG integration" not in missing else None
    if not typed_apkg:
        missing.append("typed-APKG integration") if "typed-APKG integration" not in missing else None

    if missing:
        report["result"] = "qemu-package-checkpoint-passed"
        report["release_gate_missing"] = missing
    else:
        report["result"] = "non-hardware-release-gates-passed"
        report["release_gate_missing"] = []
    report["completed_utc_epoch"] = time.time()
    write_report(report_path, report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
