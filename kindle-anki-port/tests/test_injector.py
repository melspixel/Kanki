#!/usr/bin/env python3
from __future__ import annotations

import json
import subprocess
import tempfile
import time
from pathlib import Path


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


def main() -> int:
    project = Path(__file__).resolve().parents[1]
    commit = json.loads((project / "upstream.lock.json").read_text())["commit"]
    with tempfile.TemporaryDirectory(prefix="kap-inject-test-") as tmp:
        anki = Path(tmp) / "anki"
        write_fixture(anki, commit)
        command = [
            "python3",
            str(project / "tools/inject_into_anki.py"),
            "--project",
            str(project),
            "--anki",
            str(anki),
            "--skip-submodules",
        ]
        subprocess.run(command, check=True)
        tracked = [
            anki / "rslib/src/kap_port.rs",
            anki / "rslib/src/services/kap_bridge.rs",
            anki / ".kap-upstream-commit",
        ]
        mtimes = {path: path.stat().st_mtime_ns for path in tracked}
        time.sleep(0.02)
        subprocess.run(command, check=True)
        assert {path: path.stat().st_mtime_ns for path in tracked} == mtimes
        assert (anki / "rslib/src/kap_port.rs").is_file()
        assert (anki / "rslib/src/services/kap_bridge.rs").is_file()
        assert (anki / "rslib/src/lib.rs").read_text().count("pub mod kap_port;") == 1
        assert (anki / "rslib/src/services.rs").read_text().count("pub(crate) mod kap_bridge;") == 1
        assert (anki / "rslib/Cargo.toml").read_text().count('crate-type = ["rlib", "cdylib"]') == 1
    print("test_injector: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
