#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "testenv" / "scripts" / "run-armhf-gates.sh"


def run(*args: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        cwd=cwd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def init_repo(path: Path) -> None:
    path.mkdir(parents=True)
    run("git", "init", "-q", cwd=path)
    run("git", "config", "user.name", "KAP Test", cwd=path)
    run("git", "config", "user.email", "kap-test@example.invalid", cwd=path)


def commit_all(path: Path, message: str) -> str:
    run("git", "add", "-A", cwd=path)
    run("git", "commit", "-q", "-m", message, cwd=path)
    return run("git", "rev-parse", "HEAD", cwd=path).stdout.strip()


class ArmhfProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_obj = tempfile.TemporaryDirectory(prefix="kap-armhf-provenance-")
        self.tmp = Path(self.tmp_obj.name)
        self.project = self.tmp / "project"
        self.anki = self.tmp / "anki"
        self.toolchain = self.tmp / "toolchain"
        self.cargo_home = self.tmp / "cargo-home"
        self.out = self.tmp / "out"
        self.marker = self.tmp / "cargo-called"
        self.protoc = self.tmp / "protoc"

        init_repo(self.anki)
        (self.anki / "README").write_text("pinned\n", encoding="utf-8")
        self.anki_pin = commit_all(self.anki, "pinned anki")

        init_repo(self.project)
        (self.project / "upstream.lock.json").write_text(
            json.dumps({"commit": self.anki_pin}) + "\n", encoding="utf-8"
        )
        (self.project / "README").write_text("project\n", encoding="utf-8")
        self.project_head = commit_all(self.project, "project")

        self.toolchain.mkdir()
        self.cargo_home.mkdir()
        self.protoc.write_text("fixture\n", encoding="utf-8")
        cargo = self.toolchain / "cargo"
        cargo.write_text(
            "#!/bin/sh\n"
            "printf 'called\\n' > \"$CARGO_MARKER\"\n"
            "exit 77\n",
            encoding="utf-8",
        )
        cargo.chmod(0o755)

    def tearDown(self) -> None:
        self.tmp_obj.cleanup()

    def env(self, **overrides: str) -> dict[str, str]:
        env = os.environ.copy()
        env.update(
            {
                "PROJECT": str(self.project),
                "ANKI": str(self.anki),
                "CARGO_HOME": str(self.cargo_home),
                "PROTOC": str(self.protoc),
                "TOOLCHAIN_BIN": str(self.toolchain),
                "OUT": str(self.out),
                "SYSROOT": str(self.tmp / "fixture-sysroot"),
                "GLIBC_CEILING": "2.35",
                "CARGO_MARKER": str(self.marker),
            }
        )
        env.update(overrides)
        return env

    def invoke(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        self.marker.unlink(missing_ok=True)
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.tmp,
            env=self.env(**overrides),
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def assert_blocked_before_cargo(self, proc: subprocess.CompletedProcess[str], code: int) -> None:
        self.assertEqual(proc.returncode, code, proc.stdout + proc.stderr)
        self.assertFalse(self.marker.exists(), proc.stdout + proc.stderr)

    def test_clean_pinned_checkouts_reach_cargo(self) -> None:
        proc = self.invoke()
        self.assertEqual(proc.returncode, 77, proc.stdout + proc.stderr)
        self.assertTrue(self.marker.exists(), proc.stdout + proc.stderr)

    def test_invalid_build_commit_is_rejected(self) -> None:
        proc = self.invoke(BUILD_COMMIT="not-a-commit")
        self.assert_blocked_before_cargo(proc, 65)
        self.assertIn("BUILD_COMMIT must be", proc.stderr)

    def test_mismatched_project_head_is_rejected(self) -> None:
        proc = self.invoke(BUILD_COMMIT="0" * 40)
        self.assert_blocked_before_cargo(proc, 66)
        self.assertIn("does not match project HEAD", proc.stderr)

    def test_dirty_project_is_rejected(self) -> None:
        (self.project / "dirty-source.c").write_text("dirty\n", encoding="utf-8")
        proc = self.invoke()
        self.assert_blocked_before_cargo(proc, 66)
        self.assertIn("project source tree is dirty", proc.stderr)

    def test_anki_override_must_equal_lock(self) -> None:
        proc = self.invoke(ANKI_COMMIT="0" * 40)
        self.assert_blocked_before_cargo(proc, 67)
        self.assertIn("does not match upstream.lock.json", proc.stderr)

    def test_anki_checkout_head_must_equal_lock(self) -> None:
        (self.anki / "README").write_text("different head\n", encoding="utf-8")
        commit_all(self.anki, "different anki")
        proc = self.invoke()
        self.assert_blocked_before_cargo(proc, 67)
        self.assertIn("Anki checkout HEAD does not match", proc.stderr)


if __name__ == "__main__":
    if shutil.which("git") is None:
        raise SystemExit("git is required")
    unittest.main()
