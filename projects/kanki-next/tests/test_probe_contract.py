#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--header", type=Path, required=True)
    args = parser.parse_args()

    js = (args.root / "web" / "reviewer.js").read_text(encoding="utf-8")
    css = (args.root / "web" / "reviewer.css").read_text(encoding="utf-8")
    template = (args.root / "web" / "probe.html.in").read_text(encoding="utf-8")
    header = args.header.read_text(encoding="utf-8")

    for forbidden in ("=>", "const ", "let ", "`", "Promise", "class "):
        if forbidden in js:
            fail(f"reviewer.js contains old-WebKit-incompatible token: {forbidden!r}")

    for forbidden in ("display: grid", "display:grid", "var(", "clamp("):
        if forbidden in css:
            fail(f"reviewer.css contains unsupported construct: {forbidden!r}")

    if template.count('id="qa"') != 1:
        fail("probe must contain exactly one persistent #qa root")
    if '<meta name="viewport" content="width=device-width, initial-scale=1">' not in template:
        fail("probe viewport contract changed")
    if "showQuestion" not in js or "showAnswer" not in js:
        fail("persistent reviewer public API missing")
    if "replaceChild(newScript" not in js:
        fail("card scripts would not be re-executed after innerHTML insertion")
    if "card\" + (ordinal + 1)" not in js:
        fail("cardN body class contract missing")
    if "KANKI_NEXT_PROBE_HTML" not in header:
        fail("generated C header missing probe symbol")
    if "@@" in header:
        fail("generated C header contains unresolved placeholder")

    size = args.header.stat().st_size
    if not (10_000 <= size <= 400_000):
        fail(f"generated probe asset has suspicious size: {size}")

    html_markers = re.findall(r"KANKI_PROBE", header)
    if len(html_markers) < 2:
        fail("generated probe lost diagnostic markers")

    print("test_probe_contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
