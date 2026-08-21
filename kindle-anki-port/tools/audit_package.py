#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import stat
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

REQUIRED = {
    "extensions/kindle-anki-port/kap-app",
    "extensions/kindle-anki-port/kap-audio",
    "extensions/kindle-anki-port/kap-sync",
    "extensions/kindle-anki-port/libanki-kindle.so",
    "extensions/kindle-anki-port/scripts/launch.sh",
    "extensions/kindle-anki-port/scripts/sync.sh",
    "documents/Kindle Anki.sh",
    "documents/Kindle Anki Sync.sh",
}
FORBIDDEN_BASENAMES = {
    "collection.anki2", "media.db2", "config.ini", ".kap.pid",
    "kindle-anki-port.log",
}
FORBIDDEN_TEXT = [
    re.compile(pattern, re.I)
    for pattern in [r"\bRAnki\b", r"rewrite-v1", r"LD_PRELOAD", r"COCA-English"]
]
TEXT_SUFFIXES = {".sh", ".js", ".css", ".html", ".json", ".md", ".txt", ".ini"}
CREDENTIAL_PATTERN = re.compile(
    r"(?im)^(?![ \t]*#).*\b(ankiweb|hkey|sync[_-]?key)[ \t]*[:=][ \t]*(?![\"']?\$)([^\s#\"']+)"
)


def safe_path(name: str) -> bool:
    path = PurePosixPath(name)
    return not path.is_absolute() and ".." not in path.parts and "" not in path.parts


def audit_zip(path: Path) -> list[str]:
    errors: list[str] = []
    with zipfile.ZipFile(path) as archive:
        names = {info.filename.rstrip("/") for info in archive.infolist() if not info.is_dir()}
        for info in archive.infolist():
            name = info.filename.rstrip("/")
            if not name:
                continue
            if not safe_path(name):
                errors.append(f"unsafe path: {name}")
                continue
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                errors.append(f"symlink is forbidden: {name}")
            if PurePosixPath(name).name in FORBIDDEN_BASENAMES:
                errors.append(f"forbidden user/runtime file: {name}")
            if PurePosixPath(name).suffix.lower() in TEXT_SUFFIXES and info.file_size <= 2_000_000:
                text = archive.read(info).decode("utf-8", "replace")
                for pattern in FORBIDDEN_TEXT:
                    if pattern.search(text):
                        errors.append(f"forbidden dependency marker {pattern.pattern!r}: {name}")
                if CREDENTIAL_PATTERN.search(text):
                    errors.append(f"package appears to contain a sync credential: {name}")
        missing = REQUIRED - names
        errors.extend(f"missing required file: {name}" for name in sorted(missing))
    return errors


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("package", type=Path)
    parser.add_argument("--sha256-out", type=Path)
    args = parser.parse_args()
    if not args.package.is_file():
        raise SystemExit(f"package does not exist: {args.package}")
    try:
        errors = audit_zip(args.package)
    except zipfile.BadZipFile as error:
        raise SystemExit(f"invalid zip: {error}") from error
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    digest = sha256(args.package)
    if args.sha256_out:
        args.sha256_out.write_text(f"{digest}  {args.package.name}\n", encoding="utf-8")
    print(f"audit_package: ok sha256={digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
