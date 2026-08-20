#!/usr/bin/env python3
from __future__ import annotations

import argparse
import base64
from pathlib import Path


def c_string_literal(text: str) -> str:
    lines = text.splitlines(keepends=True)
    encoded = []
    for line in lines:
        escaped = (
            line.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\r", "\\r")
            .replace("\n", "\\n")
        )
        encoded.append(f'    "{escaped}"')
    if not encoded:
        encoded.append('    ""')
    return "\n".join(encoded)


def build_html(root: Path, image_path: Path) -> str:
    template = (root / "web" / "probe.html.in").read_text(encoding="utf-8")
    css = (root / "web" / "reviewer.css").read_text(encoding="utf-8")
    javascript = (root / "web" / "reviewer.js").read_text(encoding="utf-8")
    image_data = base64.b64encode(image_path.read_bytes()).decode("ascii")
    image_uri = "data:image/png;base64," + image_data
    html = template.replace("@@REVIEWER_CSS@@", css)
    html = html.replace("@@REVIEWER_JS@@", javascript)
    html = html.replace("@@PROBE_IMAGE@@", image_uri)
    if "@@" in html:
        raise SystemExit("unresolved probe template placeholder")
    return html


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()

    html = build_html(args.root, args.image)
    output = """#ifndef KANKI_NEXT_PROBE_ASSET_H
#define KANKI_NEXT_PROBE_ASSET_H

static const char KANKI_NEXT_PROBE_HTML[] =
%s;

#endif
""" % c_string_literal(html)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(output, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
