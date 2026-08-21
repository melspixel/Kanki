#!/usr/bin/env python3
from __future__ import annotations

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "testenv" / "scripts" / "run-host-backend-gates.sh"


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


class HostBackendProvenanceTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp_obj = tempfile.TemporaryDirectory(prefix="kap-host-provenance-")
        self.tmp = Path(self.tmp_obj.name)
        self.project = self.tmp / "project"
        self.anki = self.tmp / "anki"
        self.fakebin = self.tmp / "fakebin"
        self.cargo_home = self.tmp / "cargo-home"
        self.inject_marker = self.tmp / "inject-called"
        self.cargo_log = self.tmp / "cargo.log"
        self.protoc = self.tmp / "protoc"

        init_repo(self.anki)
        (self.anki / "README").write_text("pinned\n", encoding="utf-8")
        self.anki_pin = commit_all(self.anki, "pinned anki")

        init_repo(self.project)
        (self.project / "tools").mkdir()
        (self.project / "tools" / "inject_into_anki.py").write_text(
            "import os, pathlib\n"
            "pathlib.Path(os.environ['INJECT_MARKER']).write_text('called\\n')\n",
            encoding="utf-8",
        )
        (self.project / "upstream.lock.json").write_text(
            json.dumps({"commit": self.anki_pin}) + "\n", encoding="utf-8"
        )
        (self.project / "README").write_text("project\n", encoding="utf-8")
        self.project_head = commit_all(self.project, "project")

        self.fakebin.mkdir()
        self.cargo_home.mkdir()
        self.protoc.write_text("fixture\n", encoding="utf-8")
        cargo = self.fakebin / "cargo"
        cargo.write_text(
            "#!/bin/sh\n"
            "printf '%s\\n' \"$1\" >> \"$HOST_CARGO_LOG\"\n"
            "if [ \"$1\" = build ]; then mkdir -p target/release; : > target/release/libanki.so; fi\n"
            "exit 0\n",
            encoding="utf-8",
        )
        cargo.chmod(0o755)
        nm = self.fakebin / "nm"
        nm.write_text(
            "#!/bin/sh\n"
            "printf '00000000 T kap_open_collection_json\\n'\n",
            encoding="utf-8",
        )
        nm.chmod(0o755)

    def tearDown(self) -> None:
        self.tmp_obj.cleanup()

    def invoke(self, **overrides: str) -> subprocess.CompletedProcess[str]:
        self.inject_marker.unlink(missing_ok=True)
        self.cargo_log.unlink(missing_ok=True)
        env = os.environ.copy()
        env.update(
            {
                "PROJECT": str(self.project),
                "ANKI": str(self.anki),
                "CARGO_HOME": str(self.cargo_home),
                "PROTOC": str(self.protoc),
                "INJECT_MARKER": str(self.inject_marker),
                "HOST_CARGO_LOG": str(self.cargo_log),
                "PATH": f"{self.fakebin}:{env['PATH']}",
            }
        )
        env.update(overrides)
        return subprocess.run(
            ["bash", str(SCRIPT)],
            cwd=self.tmp,
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

    def assert_blocked_before_injection(self, proc: subprocess.CompletedProcess[str], code: int) -> None:
        self.assertEqual(proc.returncode, code, proc.stdout + proc.stderr)
        self.assertFalse(self.inject_marker.exists(), proc.stdout + proc.stderr)
        self.assertFalse(self.cargo_log.exists(), proc.stdout + proc.stderr)

    def test_clean_pinned_checkouts_complete_fixture_gate(self) -> None:
        proc = self.invoke()
        self.assertEqual(proc.returncode, 0, proc.stdout + proc.stderr)
        self.assertTrue(self.inject_marker.exists(), proc.stdout + proc.stderr)
        self.assertEqual(self.cargo_log.read_text(encoding="utf-8"), "check\ntest\nbuild\n")
        self.assertIn("kap_open_collection_json", proc.stdout)

    def test_invalid_build_commit_is_rejected(self) -> None:
        proc = self.invoke(BUILD_COMMIT="not-a-commit")
        self.assert_blocked_before_injection(proc, 65)
        self.assertIn("BUILD_COMMIT must be", proc.stderr)

    def test_mismatched_project_head_is_rejected(self) -> None:
        proc = self.invoke(BUILD_COMMIT="0" * 40)
        self.assert_blocked_before_injection(proc, 66)
        self.assertIn("does not match project HEAD", proc.stderr)

    def test_dirty_project_is_rejected(self) -> None:
        (self.project / "dirty-source.rs").write_text("dirty\n", encoding="utf-8")
        proc = self.invoke()
        self.assert_blocked_before_injection(proc, 66)
        self.assertIn("project source tree is dirty", proc.stderr)

    def test_anki_checkout_head_must_equal_lock(self) -> None:
        (self.anki / "README").write_text("different head\n", encoding="utf-8")
        commit_all(self.anki, "different anki")
        proc = self.invoke()
        self.assert_blocked_before_injection(proc, 67)
        self.assertIn("Anki checkout HEAD does not match", proc.stderr)


if __name__ == "__main__":
    unittest.main()
