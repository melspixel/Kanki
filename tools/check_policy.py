#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
renderer_files = [
    ROOT / "assets/reviewer/reviewer.css",
    ROOT / "assets/reviewer/reviewer.js",
    ROOT / "crates/kanki-renderer/src/lib.rs",
]
text = "\n".join(path.read_text(encoding="utf-8") for path in renderer_files).lower()
forbidden = ["coca-english", "dictionary-logo", ".pos-badge", ".word {"]
errors = [f"deck-specific token in generic renderer: {item}" for item in forbidden if item in text]
if "svg {" in (ROOT / "assets/reviewer/reviewer.css").read_text(encoding="utf-8"):
    errors.append("generic SVG sizing rule is forbidden")
if "id=\"qa\"" not in (ROOT / "assets/reviewer/reviewer.html").read_text(encoding="utf-8"):
    errors.append("persistent #qa root is missing")
if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("renderer policy: pass")
