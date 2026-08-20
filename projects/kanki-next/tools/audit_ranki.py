#!/usr/bin/env python3
from __future__ import annotations

import argparse
import configparser
import hashlib
import json
import re
import zipfile
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError as exc:  # pragma: no cover - Python 3.11+ in CI
    raise SystemExit("Python 3.11+ is required for tomllib") from exc


class AuditError(RuntimeError):
    pass


def require(pattern: str, text: str, label: str, flags: int = 0) -> None:
    if re.search(pattern, text, flags) is None:
        raise AuditError(f"missing upstream renderer feature: {label}")


def audit_source(source: Path) -> dict[str, object]:
    base_path = source / "views" / "base.vala"
    review_path = source / "views" / "review.vala"
    if not base_path.is_file() or not review_path.is_file():
        raise AuditError("source root does not contain views/base.vala and views/review.vala")

    base = base_path.read_text(encoding="utf-8")
    review = review_path.read_text(encoding="utf-8")

    require(
        r"get_screen\(\)\.get_width\(\)\s*/\s*600\.0",
        base,
        "physical screen width divided by 600",
    )
    require(
        r"keyfile\.get_double\(\s*\"General\"\s*,\s*\"scale\"\s*\)\s*\*\s*scaling",
        review,
        "WebView zoom multiplies config scale by GTK scale",
        re.S,
    )
    require(
        r"<property name=\"zoom_level\">2</property>",
        review,
        "WebView template zoom_level=2",
    )
    require(
        r"<div class=\\\"card kindle\\\">",
        review,
        "extra card/kindle wrapper",
    )
    load_calls = len(re.findall(r"card_content\.load_html_string\s*\(", review))
    if load_calls < 2:
        raise AuditError("expected separate question and answer load_html_string calls")

    return {
        "screen_scale_expression": "screen_width/600.0",
        "webview_zoom_expression": "General.scale*screen_scale",
        "template_zoom_level": 2,
        "extra_card_wrapper": True,
        "load_html_string_calls": load_calls,
        "sets_full_content_zoom": "set_full_content_zoom" in review,
        "sets_w3c_css_pixels": "set_useW3CStd_cssPixelsPerInch" in review,
        "queries_pixel_density": "get_pixel_density" in review,
    }


def find_zip_member(archive: zipfile.ZipFile, name: str) -> str:
    candidates = [member for member in archive.namelist() if Path(member).name == name]
    if len(candidates) != 1:
        raise AuditError(f"expected exactly one {name}, found {len(candidates)}")
    return candidates[0]


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def audit_package(package: Path, lock: dict[str, object]) -> dict[str, object]:
    ranki_lock = lock["ranki"]
    with zipfile.ZipFile(package) as archive:
        armhf_name = find_zip_member(archive, "ranki-armhf")
        armel_name = find_zip_member(archive, "ranki-armel")
        config_name = find_zip_member(archive, "config.ini")
        hashes = {
            "armhf": sha256_bytes(archive.read(armhf_name)),
            "armel": sha256_bytes(archive.read(armel_name)),
        }
        expected = {
            "armhf": str(ranki_lock["armhf_binary_sha256"]),
            "armel": str(ranki_lock["armel_binary_sha256"]),
        }
        if hashes != expected:
            raise AuditError(
                "release binary hashes changed: "
                + json.dumps({"expected": expected, "actual": hashes}, sort_keys=True)
            )

        parser = configparser.ConfigParser()
        config_text = archive.read(config_name).decode("utf-8")
        parser.read_string(config_text)
        if not parser.has_option("General", "scale"):
            raise AuditError("release config.ini has no General.scale")
        scale = parser.getfloat("General", "scale")
        if not (0.1 <= scale <= 10.0):
            raise AuditError(f"release General.scale is implausible: {scale}")

    return {
        "armhf_sha256": hashes["armhf"],
        "armel_sha256": hashes["armel"],
        "general_scale": scale,
        "pw6_1264_requested_zoom": scale * (1264.0 / 600.0),
    }


def load_lock(path: Path) -> dict[str, object]:
    with path.open("rb") as stream:
        return tomllib.load(stream)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--package", type=Path, required=True)
    parser.add_argument("--lock", type=Path, required=True)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    lock = load_lock(args.lock)
    try:
        report = {
            "format": 1,
            "source": audit_source(args.source),
            "package": audit_package(args.package, lock),
            "pinned_commit": lock["ranki"]["commit"],
        }
    except (AuditError, OSError, zipfile.BadZipFile, ValueError) as exc:
        raise SystemExit(f"RAnki audit failed: {exc}") from exc

    rendered = json.dumps(report, indent=2, sort_keys=True) + "\n"
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(rendered, encoding="utf-8")
    print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
