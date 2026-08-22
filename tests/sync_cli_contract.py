#!/usr/bin/env python3
"""Fail-closed runtime contract for the native sync CLI option parser."""

from __future__ import annotations

import os
import shlex
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "device/kanki_sync_cli.c"


def run(binary: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(binary), *arguments],
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def require_status(
    result: subprocess.CompletedProcess[str], expected: int, description: str
) -> None:
    if result.returncode != expected:
        raise SystemExit(
            f"{description}: expected status {expected}, got {result.returncode}\n"
            f"stdout={result.stdout!r}\nstderr={result.stderr!r}"
        )


with tempfile.TemporaryDirectory(prefix="kanki-sync-cli-") as temporary:
    work = Path(temporary)
    binary = work / "kanki-sync"
    compiler = shlex.split(os.environ.get("HOST_CC", "cc"))
    subprocess.run(
        [
            *compiler,
            "-std=c11",
            "-D_POSIX_C_SOURCE=200809L",
            "-fsigned-char",
            "-Wall",
            "-Wextra",
            "-Werror",
            str(SOURCE),
            f"-I{ROOT / 'bridge'}",
            "-ldl",
            "-o",
            str(binary),
        ],
        check=True,
    )

    for arguments in (
        ("--full-upload", "--full-download"),
        ("--full-download", "--full-upload"),
    ):
        result = run(binary, *arguments)
        require_status(result, 64, f"conflicting directions {arguments}")
        if "mutually exclusive" not in result.stderr:
            raise SystemExit(
                f"conflicting directions {arguments} did not explain rejection: "
                f"{result.stderr!r}"
            )

    missing_config = str(work / "missing.ini")
    for arguments in (
        ("--full-upload", "--full-upload", "--config", missing_config),
        ("--full-download", "--full-download", "--config", missing_config),
    ):
        result = run(binary, *arguments)
        require_status(result, 65, f"duplicate identical direction {arguments[:2]}")
        if "missing hkey" not in result.stderr:
            raise SystemExit(
                f"duplicate identical direction {arguments[:2]} was rejected by the "
                f"wrong gate: {result.stderr!r}"
            )

print("sync CLI contract: pass")
