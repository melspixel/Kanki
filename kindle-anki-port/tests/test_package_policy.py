#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
import zipfile
from pathlib import PurePosixPath


FORBIDDEN_BASENAMES = {
    "collection.anki2",
    "collection.media",
    "media.db2",
    "config.ini",
}
FORBIDDEN_SUFFIXES = (".log", ".pid")
FORBIDDEN_TEXT = ("LD_PRELOAD", "rewrite-v1", "ranki-armhf", "ranki-armel")
REQUIRED = {
    "extensions/kindle-anki-port/kap-app",
    "extensions/kindle-anki-port/kap-audio",
    "extensions/kindle-anki-port/kap-sync",
    "extensions/kindle-anki-port/libanki-kindle.so",
    "extensions/kindle-anki-port/BUILD.json",
    "extensions/kindle-anki-port/MANIFEST.sha256",
    "documents/Kindle Anki.sh",
}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("archive")
    args = parser.parse_args()

    with zipfile.ZipFile(args.archive) as archive:
        bad_crc = archive.testzip()
        if bad_crc:
            raise SystemExit(f"FAIL: bad ZIP member {bad_crc}")
        names = {name.rstrip("/") for name in archive.namelist() if not name.endswith("/")}
        missing = REQUIRED - names
        if missing:
            raise SystemExit(f"FAIL: package missing {sorted(missing)}")
        for name in names:
            path = PurePosixPath(name)
            lower = path.name.lower()
            if lower in FORBIDDEN_BASENAMES or lower.endswith(FORBIDDEN_SUFFIXES):
                raise SystemExit(f"FAIL: package contains forbidden state file {name}")
            if "collection.media/" in name.lower():
                raise SystemExit(f"FAIL: package contains user media {name}")
            info = archive.getinfo(name)
            if info.file_size <= 2_000_000:
                try:
                    text = archive.read(name).decode("utf-8")
                except UnicodeDecodeError:
                    continue
                for token in FORBIDDEN_TEXT:
                    if token.lower() in text.lower():
                        raise SystemExit(f"FAIL: package text {name} contains {token}")
                if re.search(r"(?im)^(?![ \t]*#).*\b(ankiweb|hkey|sync[_-]?key)[ \t]*[:=][ \t]*(?![\"']?\$)([^\s#\"']+)", text):
                    raise SystemExit(f"FAIL: package appears to contain a sync credential in {name}")

    print("test_package_policy: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
