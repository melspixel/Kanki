#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "testenv" / "scripts" / "prepare-sysroot.sh"


def tree_digest(root: Path) -> str:
    records = []
    for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
        rel = path.relative_to(root).as_posix()
        st = path.lstat()
        record = {"mode": format(stat.S_IMODE(st.st_mode), "04o"), "path": rel}
        if stat.S_ISREG(st.st_mode):
            record.update(type="file", sha256=hashlib.sha256(path.read_bytes()).hexdigest())
        elif stat.S_ISDIR(st.st_mode):
            record["type"] = "dir"
        elif stat.S_ISLNK(st.st_mode):
            record.update(type="symlink", target=os.readlink(path))
        elif stat.S_ISFIFO(st.st_mode):
            record["type"] = "fifo"
        else:
            raise AssertionError(f"unexpected test entry: {rel}")
        records.append(record)
    payload = json.dumps(
        {"algorithm": "kap-rootfs-tree-v1", "entries": records},
        ensure_ascii=False,
        separators=(",", ":"),
        sort_keys=True,
    ).encode()
    return hashlib.sha256(payload).hexdigest()


def populate(root: Path) -> None:
    (root / "lib").mkdir(parents=True)
    (root / "usr/lib").mkdir(parents=True)
    (root / "lib/ld-linux-armhf.so.3").write_bytes(b"loader\n")
    (root / "usr/lib/libfoo.so").write_bytes(b"library\n")
    os.symlink("libfoo.so", root / "usr/lib/libfoo.so.1")


def run(root: Path, expected: str, output: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(SCRIPT), str(root), expected, str(output)],
        text=True,
        capture_output=True,
    )


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kap-sysroot-test-") as tmp_text:
        tmp = Path(tmp_text)
        a = tmp / "a"
        b = tmp / "nested/location/b"
        populate(a)
        populate(b)
        expected = tree_digest(a)
        assert tree_digest(b) == expected

        out_a = tmp / "a.json"
        result = run(a, expected, out_a)
        assert result.returncode == 0, result.stderr
        data = json.loads(out_a.read_text())
        assert data["schema"] == 2
        assert data["tree_manifest_algorithm"] == "kap-rootfs-tree-v1"
        assert data["tree_manifest_sha256"] == expected
        assert data["dynamic_linker"] == "/lib/ld-linux-armhf.so.3"

        out_b = tmp / "b.json"
        result = run(b, expected, out_b)
        assert result.returncode == 0, result.stderr

        (b / "usr/lib/libfoo.so.1").unlink()
        os.symlink("different.so", b / "usr/lib/libfoo.so.1")
        result = run(b, expected, tmp / "mutated.json")
        assert result.returncode == 3, (result.returncode, result.stderr)
        assert "rootfs tree hash mismatch" in result.stderr

        wrong = "0" * 64
        absent = tmp / "wrong.json"
        result = run(a, wrong, absent)
        assert result.returncode == 3
        assert not absent.exists()

        missing = tmp / "missing"
        missing.mkdir()
        result = run(missing, tree_digest(missing), tmp / "missing.json")
        assert result.returncode == 4
        assert "lacks /lib/ld-linux-armhf.so.3" in result.stderr

    print("test_prepare_sysroot: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
