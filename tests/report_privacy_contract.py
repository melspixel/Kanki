#!/usr/bin/env python3
"""Keep redacted report staging private, unique and failure-atomic."""

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPORT = (ROOT / "scripts/kanki-report.sh").read_text(encoding="utf-8")


def fail(message: str) -> None:
    raise SystemExit(f"report privacy contract: FAIL: {message}")


def require(fragment: str, message: str) -> None:
    if fragment not in REPORT:
        fail(message)


def forbid(fragment: str, message: str) -> None:
    if fragment in REPORT:
        fail(message)


require("umask 077", "report files are not created with private permissions")
require(
    'WORK="$OUT_ROOT/kanki-report-$STAMP-$$"',
    "working directory is not unique to the report process",
)
require(
    'ARCHIVE_PART="$OUT_ROOT/.kanki-report-$STAMP-$$.tar.gz.partial"',
    "archive is not staged through a unique partial path",
)
require('if [ -L "$OUT_ROOT" ]', "symbolic report output root is not refused")
require('chmod 700 "$OUT_ROOT"', "report output root is not private mode 0700")
require("cleanup_report() {", "report has no failure cleanup function")
require("WORK_CREATED=0", "cleanup does not track ownership of the work tree")
require("ARCHIVE_PART_OWNED=0", "cleanup does not track the partial archive")
require("trap cleanup_report EXIT", "exit cleanup trap is absent")
require("trap 'exit 74' HUP INT TERM", "signal handling does not exit through cleanup")
require('mkdir "$WORK"', "working directory is not created atomically")
forbid('mkdir -p "$WORK"', "working directory can silently reuse stale content")
require(
    'tar -czf "$ARCHIVE_PART" "$WORK_NAME"',
    "tar writes directly to the final archive path",
)
require(
    'mv "$ARCHIVE_PART" "$ARCHIVE"',
    "completed archive is not published atomically",
)
forbid(
    "report directory left at",
    "a report failure deliberately leaves private staging content behind",
)

for forbidden_source in [
    'copy_if_readable "$DIR/config.ini"',
    'copy_if_readable "/mnt/us/anki_data/collection.anki2"',
    'copy_if_readable "/mnt/us/anki_data/collection.media"',
    'copy_if_readable "$RENDER_DEBUG/card-',
    'copy_if_readable "$RENDER_PREVIOUS/card-',
]:
    forbid(forbidden_source, f"default bundle includes forbidden source: {forbidden_source}")

print("report privacy contract: pass")
