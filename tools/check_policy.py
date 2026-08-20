#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
assets = [
    ROOT / "assets/reviewer/reviewer.css",
    ROOT / "assets/reviewer/reviewer.js",
]
renderer_rs = (ROOT / "crates/kanki-renderer/src/lib.rs").read_text(encoding="utf-8")
production_renderer_rs = renderer_rs.split("#[cfg(test)]", 1)[0]
text = (
    "\n".join(path.read_text(encoding="utf-8") for path in assets)
    + "\n"
    + production_renderer_rs
).lower()
forbidden = ["coca-english", "dictionary-logo", ".pos-badge", ".word {"]
errors = [
    f"deck-specific token in generic renderer: {item}"
    for item in forbidden
    if item in text
]
css = (ROOT / "assets/reviewer/reviewer.css").read_text(encoding="utf-8")
if re.search(r"(?m)^\s*svg\s*\{", css):
    errors.append("generic SVG sizing rule is forbidden")
if "id=\"qa\"" not in (
    ROOT / "assets/reviewer/reviewer.html"
).read_text(encoding="utf-8"):
    errors.append("persistent #qa root is missing")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("renderer policy: pass")
