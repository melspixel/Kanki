#!/usr/bin/env python3
from __future__ import annotations
import argparse
import re
from pathlib import Path

BANNED_PRODUCT_MARKERS = (
    "COCA-English",
    "4000 Essential English Words",
    "Advanced Vocabulary Complete",
    "百词斩",
    "新东方雅思",
)
BANNED_ES6 = (
    r"=>",
    r"\bconst\b",
    r"\blet\b",
    r"\bclass\s+[A-Za-z_$]",
    r"`",
    r"\bPromise\b",
)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    args = parser.parse_args()
    web = args.project / "web"
    files = sorted(web.glob("*"))
    require(bool(files), "web runtime is absent")
    text = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in files
        if path.suffix in {".js", ".css", ".html"}
    )
    for marker in BANNED_PRODUCT_MARKERS:
        require(marker not in text, f"deck/product-specific marker present: {marker}")
    javascript = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in files
        if path.suffix == ".js"
    )
    for pattern in BANNED_ES6:
        require(not re.search(pattern, javascript), f"legacy WebKit-incompatible JS token: {pattern}")
    require("qa" in javascript.lower(), "persistent reviewer #qa contract is not referenced")
    require(
        "type" in javascript.lower() and ("answer" in javascript.lower() or "input" in javascript.lower()),
        "typed-answer lifecycle is not represented",
    )
    require(
        "audio" in javascript.lower() or "replay" in javascript.lower() or "av" in javascript.lower(),
        "semantic AV/replay lifecycle is not represented",
    )
    require(
        "scroll" in javascript.lower() or "page" in javascript.lower(),
        "long-card paging/scroll lifecycle is not represented",
    )
    print("reviewer contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
