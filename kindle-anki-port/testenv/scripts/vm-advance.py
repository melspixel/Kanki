#!/usr/bin/env python3
"""Run one durable VM-side Kindle Anki build checkpoint.

This driver never marks hardware acceptance. It records every command, exit code,
and artifact digest so another worker can resume without chat context.
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


def run(name: str, command: list[str], *, cwd: Path, env: dict[str, str], logdir: Path, timeout: int) -> dict[str, object]:
    started = time.time()
    proc = subprocess.run(
        command,
        cwd=cwd,
        env={**os.environ, **env},
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    path = logdir / f"{name}.log"
    path.write_text(proc.stdout, encoding="utf-8", errors="replace")
    return {
        "name": name,
        "command": command,
        "cwd": str(cwd),
        "returncode": proc.returncode,
        "seconds": round(time.time() - started, 3),
        "log": str(path),
    }


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--anki", type=Path, required=True)
    parser.add_argument("--work", type=Path, required=True)
    parser.add_argument("--kindle-toolchain-bin", type=Path)
    args = parser.parse_args()

    project = args.project.resolve()
    source = args.anki.resolve()
    work = args.work.resolve()
    checkout = work / "anki"
    logs = work / "logs"
    logs.mkdir(parents=True, exist_ok=True)
    if checkout.exists():
        shutil.rmtree(checkout)
    shutil.copytree(source, checkout, symlinks=True)

    report: dict[str, object] = {
        "schema": 1,
        "started_utc_epoch": time.time(),
        "project": str(project),
        "anki_source": str(source),
        "steps": [],
        "artifacts": {},
        "hardware_acceptance": "not-run",
    }
    env = {"PROTOC": "/usr/bin/protoc", "CARGO_TERM_COLOR": "never"}

    inject = run(
        "inject",
        [
            "python3",
            str(project / "tools/inject_into_anki.py"),
            "--project",
            str(project),
            "--anki",
            str(checkout),
            "--manifest",
            str(work / "injection-manifest.json"),
        ],
        cwd=project,
        env=env,
        logdir=logs,
        timeout=600,
    )
    report["steps"].append(inject)
    if inject["returncode"] != 0:
        (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
        return 1

    for name, command, timeout in (
        ("cargo-check", ["cargo", "check", "-p", "anki", "--features", "rustls"], 3600),
        ("cargo-test", ["cargo", "test", "-p", "anki", "--features", "rustls", "kap_port::tests", "--lib", "--no-fail-fast"], 3600),
        ("cargo-release", ["cargo", "build", "-p", "anki", "--features", "rustls", "--release"], 7200),
    ):
        step = run(name, command, cwd=checkout, env=env, logdir=logs, timeout=timeout)
        report["steps"].append(step)
        if step["returncode"] != 0:
            (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            return 1

    host_library = checkout / "target/release/libanki.so"
    if not host_library.is_file():
        raise SystemExit("host libanki.so was not produced")
    report["artifacts"]["host_libanki_sha256"] = digest(host_library)

    if args.kindle_toolchain_bin:
        bindir = args.kindle_toolchain_bin.resolve()
        gcc = bindir / "arm-kindlehf-linux-gnueabihf-gcc"
        target = "armv7-unknown-linux-gnueabihf"
        cross_env = {
            **env,
            "PATH": f"{bindir}:{os.environ.get('PATH', '')}",
            "CARGO_TARGET_ARMV7_UNKNOWN_LINUX_GNUEABIHF_LINKER": str(gcc),
            "CC_armv7_unknown_linux_gnueabihf": str(gcc),
            "CXX_armv7_unknown_linux_gnueabihf": str(bindir / "arm-kindlehf-linux-gnueabihf-g++"),
            "AR_armv7_unknown_linux_gnueabihf": str(bindir / "arm-kindlehf-linux-gnueabihf-ar"),
        }
        cross = run(
            "cargo-armhf",
            ["cargo", "build", "-p", "anki", "--features", "rustls", "--release", "--target", target],
            cwd=checkout,
            env=cross_env,
            logdir=logs,
            timeout=7200,
        )
        report["steps"].append(cross)
        if cross["returncode"] != 0:
            (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
            return 1
        arm_library = checkout / f"target/{target}/release/libanki.so"
        report["artifacts"]["armhf_libanki_sha256"] = digest(arm_library)

    report["result"] = "software-build-gates-passed"
    report["completed_utc_epoch"] = time.time()
    (work / "report.json").write_text(json.dumps(report, indent=2) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
