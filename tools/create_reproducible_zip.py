#!/usr/bin/env python3
"""Create Kanki's deterministic package archive from an assembled tree."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
from hashlib import sha256
from pathlib import Path
import shutil
import stat
from zipfile import ZIP_DEFLATED, ZipFile, ZipInfo


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("source_date_epoch", type=int)
    return parser.parse_args()


def main() -> None:
    args = arguments()
    root = args.root.resolve(strict=True)
    output = args.output.resolve()
    if not root.is_dir():
        raise SystemExit(f"kanki-archive: package root is not a directory: {root}")
    if output == root or root in output.parents:
        raise SystemExit("kanki-archive: output must be outside the package tree")

    timestamp = datetime.fromtimestamp(args.source_date_epoch, timezone.utc)
    if timestamp.year < 1980 or timestamp.year > 2107:
        raise SystemExit("kanki-archive: source date is outside the ZIP timestamp range")
    zip_timestamp = (
        timestamp.year,
        timestamp.month,
        timestamp.day,
        timestamp.hour,
        timestamp.minute,
        timestamp.second,
    )

    files = sorted(
        (path for path in root.rglob("*") if path.is_file() or path.is_symlink()),
        key=lambda path: path.relative_to(root).as_posix(),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(output.name + ".tmp")
    temporary.unlink(missing_ok=True)
    try:
        with ZipFile(temporary, "w", compression=ZIP_DEFLATED, compresslevel=9) as archive:
            for path in files:
                if path.is_symlink():
                    raise SystemExit(f"kanki-archive: symlink is not allowed: {path}")
                metadata = path.stat()
                if not stat.S_ISREG(metadata.st_mode):
                    raise SystemExit(f"kanki-archive: non-regular file is not allowed: {path}")
                relative = path.relative_to(root).as_posix()
                info = ZipInfo(relative, date_time=zip_timestamp)
                info.create_system = 3
                info.compress_type = ZIP_DEFLATED
                info.external_attr = (
                    stat.S_IFREG | stat.S_IMODE(metadata.st_mode)
                ) << 16
                info.extra = b""
                info.comment = b""
                with path.open("rb") as source, archive.open(info, "w") as target:
                    shutil.copyfileobj(source, target, length=1024 * 1024)
        temporary.replace(output)
    finally:
        temporary.unlink(missing_ok=True)

    digest = sha256(output.read_bytes()).hexdigest()
    print(f"KANKI_ARCHIVE_SOURCE_DATE_EPOCH={args.source_date_epoch}")
    print(f"KANKI_ARCHIVE_FILE_COUNT={len(files)}")
    print(f"KANKI_ARCHIVE_SHA256={digest}")


if __name__ == "__main__":
    main()
