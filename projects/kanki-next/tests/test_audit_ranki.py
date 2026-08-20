#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def main() -> int:
    project = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="test-ranki-audit-") as tmp_text:
        tmp = Path(tmp_text)
        source = tmp / "ranki"
        (source / "views").mkdir(parents=True)
        (source / "views" / "base.vala").write_text(
            "return get_screen().get_width() / 600.0;\n", encoding="utf-8"
        )
        (source / "views" / "review.vala").write_text(
            '''<property name="zoom_level">2</property>\n'''
            '''card_content.set_zoom_level((float) (keyfile.get_double("General", "scale") * scaling));\n'''
            '''html += "<div class=\\"card kindle\\">";\n'''
            '''card_content.load_html_string(html, base_uri);\n'''
            '''card_content.load_html_string(html, base_uri);\n''',
            encoding="utf-8",
        )

        armhf = b"synthetic-armhf"
        armel = b"synthetic-armel"
        package = tmp / "ranki.zip"
        with zipfile.ZipFile(package, "w") as archive:
            archive.writestr("ranki/ranki-armhf", armhf)
            archive.writestr("ranki/ranki-armel", armel)
            archive.writestr("ranki/config.ini", "[General]\nscale=1.5\n")

        lock = tmp / "upstream.lock"
        lock.write_text(
            "format = 1\n\n"
            "[ranki]\n"
            'commit = "synthetic"\n'
            f'armhf_binary_sha256 = "{digest(armhf)}"\n'
            f'armel_binary_sha256 = "{digest(armel)}"\n',
            encoding="utf-8",
        )
        output = tmp / "report.json"
        result = subprocess.run(
            [
                "python3",
                str(project / "tools" / "audit_ranki.py"),
                "--source",
                str(source),
                "--package",
                str(package),
                "--lock",
                str(lock),
                "--output",
                str(output),
            ],
            check=True,
            text=True,
            capture_output=True,
        )
        report = json.loads(output.read_text(encoding="utf-8"))
        assert report["source"]["load_html_string_calls"] == 2
        assert report["source"]["sets_full_content_zoom"] is False
        assert abs(report["package"]["pw6_1264_requested_zoom"] - 3.16) < 1e-9
        assert json.loads(result.stdout)["pinned_commit"] == "synthetic"

    print("test_audit_ranki: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
