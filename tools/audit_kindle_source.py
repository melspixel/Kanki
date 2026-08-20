#!/usr/bin/env python3
"""Extract renderer-relevant evidence from Amazon's Kindle source bundle.

The tool intentionally emits only manifests and short matching source snippets.
It does not republish the source bundle or nested archives.
"""

from __future__ import annotations

import argparse
import io
import os
from pathlib import Path
import re
import tarfile

KEYWORDS = re.compile(r"webkit|javascriptcore|jscore|gtk|mesquite", re.I)
TEXT_EXTS = {
    ".c", ".cc", ".cpp", ".cxx", ".h", ".hh", ".hpp", ".in", ".m4",
    ".patch", ".diff", ".txt", ".mk", ".am", ".ac", ".cmake", ".vala",
}
PATTERNS = [
    "webkit_web_view_set_useW3CStd_cssPixelsPerInch",
    "webkit_web_view_set_fixed_layout",
    "webkit_web_view_render_partial",
    "webkit_web_view_resize_view_to_content",
    "webkit_web_view_set_full_content_zoom",
    "cssPixelsPerInch",
    "useW3CStd",
    "fixed_layout",
    "render_partial",
]


def interesting_name(name: str) -> bool:
    return bool(KEYWORDS.search(name))


def is_text_candidate(name: str, size: int) -> bool:
    if size > 8 * 1024 * 1024:
        return False
    suffix = Path(name).suffix.lower()
    return suffix in TEXT_EXTS or "patch" in name.lower() or "webkit" in name.lower()


def context_lines(text: str, needle: str, radius: int = 4) -> list[str]:
    lines = text.splitlines()
    out: list[str] = []
    for i, line in enumerate(lines):
        if needle.lower() in line.lower():
            lo = max(0, i - radius)
            hi = min(len(lines), i + radius + 1)
            out.append(f"--- match {needle!r} at line {i + 1} ---")
            for j in range(lo, hi):
                out.append(f"{j + 1}: {lines[j]}")
    return out


def scan_tar(tf: tarfile.TarFile, label: str, report, manifest, depth: int = 0) -> None:
    members = tf.getmembers()
    manifest.write(f"\n## {label}\n")
    for m in members:
        if interesting_name(m.name):
            manifest.write(f"{m.size}\t{m.name}\n")

    for m in members:
        if not m.isfile():
            continue
        lower = m.name.lower()
        # Scan renderer-related text files directly.
        if interesting_name(m.name) and is_text_candidate(m.name, m.size):
            try:
                f = tf.extractfile(m)
                if f is None:
                    continue
                data = f.read()
                text = data.decode("utf-8", errors="replace")
            except Exception:
                continue
            matches: list[str] = []
            for pat in PATTERNS:
                matches.extend(context_lines(text, pat))
            if matches:
                report.write(f"\n===== {label}:{m.name} =====\n")
                report.write("\n".join(matches))
                report.write("\n")

        # Recurse into small/medium renderer-related nested tar archives.
        if depth >= 2 or not interesting_name(m.name):
            continue
        if not re.search(r"\.(?:tar|tar\.gz|tgz|tar\.bz2|tbz2|tar\.xz)$", lower):
            continue
        if m.size > 900 * 1024 * 1024:
            manifest.write(f"SKIP_TOO_LARGE\t{m.size}\t{m.name}\n")
            continue
        try:
            f = tf.extractfile(m)
            if f is None:
                continue
            nested_bytes = f.read()
            with tarfile.open(fileobj=io.BytesIO(nested_bytes), mode="r:*") as nested:
                scan_tar(nested, f"{label} -> {m.name}", report, manifest, depth + 1)
        except (tarfile.TarError, OSError, EOFError) as exc:
            manifest.write(f"NESTED_ERROR\t{m.name}\t{exc}\n")


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("archive", type=Path)
    ap.add_argument("output_dir", type=Path)
    args = ap.parse_args()
    args.output_dir.mkdir(parents=True, exist_ok=True)

    report_path = args.output_dir / "renderer-api-source-matches.txt"
    manifest_path = args.output_dir / "renderer-source-manifest.txt"
    meta_path = args.output_dir / "source-audit-meta.txt"

    with report_path.open("w", encoding="utf-8") as report, manifest_path.open(
        "w", encoding="utf-8"
    ) as manifest:
        report.write("KANKI_KINDLE_SOURCE_RENDERER_AUDIT_V1\n")
        with tarfile.open(args.archive, mode="r:*") as outer:
            scan_tar(outer, args.archive.name, report, manifest)

    meta_path.write_text(
        "archive=" + args.archive.name + "\n"
        + "patterns=" + ",".join(PATTERNS) + "\n"
        + f"match_report_bytes={report_path.stat().st_size}\n"
        + f"manifest_bytes={manifest_path.stat().st_size}\n",
        encoding="utf-8",
    )


if __name__ == "__main__":
    main()
