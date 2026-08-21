#!/usr/bin/env python3
from __future__ import annotations
import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath

FORBIDDEN_NAMES = (
    re.compile(r"(^|/)(collection\.anki2|media\.db2|config\.ini|[^/]*\.pid|[^/]*\.log)$", re.I),
)
FORBIDDEN_TEXT = (
    b"LD_PRELOAD",
    b"ranki-armhf",
    b"ranki-armel",
    b"rewrite-v1",
    b"COCA-English",
    b"4000 Essential English Words",
)
REQUIRED = {
    "extensions/kindle-anki-port/kap-app",
    "extensions/kindle-anki-port/kap-audio",
    "extensions/kindle-anki-port/libanki-kindle.so",
    "extensions/kindle-anki-port/BUILD.json",
    "extensions/kindle-anki-port/MANIFEST.sha256",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package", type=Path, required=True)
    args = parser.parse_args()
    if not args.package.is_file():
        raise SystemExit("package does not exist")
    with zipfile.ZipFile(args.package) as archive:
        bad = archive.testzip()
        if bad:
            raise SystemExit(f"corrupt member: {bad}")
        names = set(archive.namelist())
        missing = sorted(REQUIRED - names)
        if missing:
            raise SystemExit(f"missing required package members: {missing}")
        for name in names:
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts:
                raise SystemExit(f"unsafe path: {name}")
            if any(regex.search(name) for regex in FORBIDDEN_NAMES):
                raise SystemExit(f"forbidden state file: {name}")
            if name.endswith("/") or archive.getinfo(name).file_size > 2_000_000:
                continue
            data = archive.read(name)
            for marker in FORBIDDEN_TEXT:
                if marker.lower() in data.lower():
                    raise SystemExit(f"forbidden marker {marker!r} in {name}")
        sync_scripts = [
            name
            for name in names
            if name.endswith("/sync.sh") or name.lower().endswith(" sync.sh")
        ]
        if sync_scripts and not any(PurePosixPath(name).name == "kap-sync" for name in names):
            raise SystemExit("sync launcher exists but kap-sync is absent")
    report = {
        "schema": 1,
        "package": args.package.name,
        "sha256": hashlib.sha256(args.package.read_bytes()).hexdigest(),
        "members": len(names),
        "result": "pass",
    }
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
