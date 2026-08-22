#!/usr/bin/env python3
from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import time
from pathlib import Path


def run(*args: str, cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        list(args),
        cwd=cwd,
        check=check,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def write_fixture(root: Path, commit: str) -> None:
    (root / "rslib/src/services").mkdir(parents=True)
    (root / "rslib/src/lib.rs").write_text("pub mod version;\n", encoding="utf-8")
    (root / "rslib/src/services.rs").write_text(
        '#![allow(dead_code)]\ninclude!(concat!(env!("OUT_DIR"), "/backend.rs"));\n',
        encoding="utf-8",
    )
    (root / "rslib/Cargo.toml").write_text("[package]\nname='anki'\n", encoding="utf-8")
    (root / "ftl/core-repo/core").mkdir(parents=True)
    (root / "ftl/qt-repo/desktop").mkdir(parents=True)
    (root / ".kap-upstream-commit").write_text(commit + "\n", encoding="utf-8")


def write_git_fixture(root: Path) -> str:
    (root / "rslib/src/services").mkdir(parents=True)
    (root / "rslib/src/lib.rs").write_text("pub mod version;\n", encoding="utf-8")
    (root / "rslib/src/services.rs").write_text(
        '#![allow(dead_code)]\ninclude!(concat!(env!("OUT_DIR"), "/backend.rs"));\n',
        encoding="utf-8",
    )
    (root / "rslib/Cargo.toml").write_text("[package]\nname='anki'\n", encoding="utf-8")
    (root / "README").write_text("official pinned fixture\n", encoding="utf-8")
    run("git", "init", "-q", cwd=root)
    run("git", "config", "user.name", "KAP Test", cwd=root)
    run("git", "config", "user.email", "kap-test@example.invalid", cwd=root)
    run("git", "add", "-A", cwd=root)
    run("git", "commit", "-q", "-m", "pinned upstream", cwd=root)
    return run("git", "rev-parse", "HEAD", cwd=root).stdout.strip()


def make_fixture_project(root: Path, source_project: Path, commit: str) -> None:
    (root / "core/src").mkdir(parents=True)
    shutil.copy2(source_project / "core/src/port.rs", root / "core/src/port.rs")
    shutil.copy2(
        source_project / "core/src/services_bridge.rs",
        root / "core/src/services_bridge.rs",
    )
    (root / "upstream.lock.json").write_text(
        json.dumps({"commit": commit}) + "\n", encoding="utf-8"
    )


def invoke(command: list[str], *, expected: int = 0) -> subprocess.CompletedProcess[str]:
    proc = subprocess.run(command, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert proc.returncode == expected, proc.stdout + proc.stderr
    return proc


def main() -> int:
    project = Path(__file__).resolve().parents[1]
    injector = project / "tools/inject_into_anki.py"
    commit = json.loads((project / "upstream.lock.json").read_text())["commit"]

    # Preserve support for a deliberately materialized non-Git source bundle,
    # where the exact upstream identity is carried by .kap-upstream-commit.
    with tempfile.TemporaryDirectory(prefix="kap-inject-test-") as tmp:
        anki = Path(tmp) / "anki"
        write_fixture(anki, commit)
        command = [
            "python3",
            str(injector),
            "--project",
            str(project),
            "--anki",
            str(anki),
            "--skip-submodules",
        ]
        invoke(command)
        tracked = [
            anki / "rslib/src/kap_port.rs",
            anki / "rslib/src/services/kap_bridge.rs",
            anki / ".kap-upstream-commit",
        ]
        mtimes = {path: path.stat().st_mtime_ns for path in tracked}
        time.sleep(0.02)
        invoke(command)
        assert {path: path.stat().st_mtime_ns for path in tracked} == mtimes
        assert (anki / "rslib/src/kap_port.rs").is_file()
        assert (anki / "rslib/src/services/kap_bridge.rs").is_file()
        assert (anki / "rslib/src/lib.rs").read_text().count("pub mod kap_port;") == 1
        assert (anki / "rslib/src/services.rs").read_text().count("pub(crate) mod kap_bridge;") == 1
        assert (anki / "rslib/Cargo.toml").read_text().count('crate-type = ["rlib", "cdylib"]') == 1

    # A release Git checkout may be dirty only by the exact deterministic
    # overlay. Unrelated tracked, staged or untracked changes must fail closed,
    # and tampering with an overlay-owned file must be detected by byte value.
    with tempfile.TemporaryDirectory(prefix="kap-inject-git-test-") as tmp:
        root = Path(tmp)
        anki = root / "anki"
        anki.mkdir()
        pinned = write_git_fixture(anki)
        fixture_project = root / "project"
        make_fixture_project(fixture_project, project, pinned)
        command = [
            "python3",
            str(injector),
            "--project",
            str(fixture_project),
            "--anki",
            str(anki),
            "--skip-submodules",
        ]
        invoke(command)
        invoke(command)

        (anki / "evil-untracked.rs").write_text("evil\n", encoding="utf-8")
        proc = invoke(command, expected=1)
        assert "unexpected=evil-untracked.rs" in proc.stderr
        (anki / "evil-untracked.rs").unlink()

        lib = anki / "rslib/src/lib.rs"
        lib.write_text(lib.read_text(encoding="utf-8") + "// tampered\n", encoding="utf-8")
        proc = invoke(command, expected=1)
        assert "overlay bytes differ from pinned HEAD + project source: rslib/src/lib.rs" in proc.stderr

        run("git", "reset", "--hard", "HEAD", cwd=anki)
        run("git", "clean", "-fd", cwd=anki)
        invoke(command)
        (anki / "README").write_text("unrelated tracked mutation\n", encoding="utf-8")
        proc = invoke(command, expected=1)
        assert "unexpected=README" in proc.stderr

        run("git", "reset", "--hard", "HEAD", cwd=anki)
        run("git", "clean", "-fd", cwd=anki)
        invoke(command)
        (anki / "staged.txt").write_text("staged mutation\n", encoding="utf-8")
        run("git", "add", "staged.txt", cwd=anki)
        proc = invoke(command, expected=1)
        assert "unexpected=staged.txt" in proc.stderr

    print("test_injector: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
