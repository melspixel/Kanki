#!/usr/bin/env python3
from __future__ import annotations

import importlib.util
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("kap_core_integration", ROOT / "tests" / "test_core_integration.py")
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


def make_zip(path: Path, entries: dict[str, bytes]) -> None:
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for name, data in entries.items():
            archive.writestr(name, data)


def main() -> int:
    with tempfile.TemporaryDirectory(prefix="kap-apkg-prepare-") as temp_text:
        temp = Path(temp_text)

        old_apkg = temp / "old.apkg"
        make_zip(
            old_apkg,
            {
                "collection.anki2": b"old-sqlite-bytes",
                "media": json.dumps({"0": "sample.mp3"}).encode(),
                "0": b"audio-bytes",
            },
        )
        collection, media, media_db = MODULE.prepare_collection(old_apkg, temp / "old")
        assert collection.read_bytes() == b"old-sqlite-bytes"
        assert (media / "sample.mp3").read_bytes() == b"audio-bytes"
        assert media_db.name == "media.db2"

        raw = temp / "new-collection"
        compressed = temp / "new-collection.zst"
        raw.write_bytes(b"new-sqlite-bytes")
        subprocess.run(["zstd", "-q", "-f", str(raw), "-o", str(compressed)], check=True)
        media_json = temp / "media-json"
        media_zstd = temp / "media-json.zst"
        media_json.write_text(json.dumps({"0": "modern.mp3"}), encoding="utf-8")
        subprocess.run(["zstd", "-q", "-f", str(media_json), "-o", str(media_zstd)], check=True)
        new_apkg = temp / "new.apkg"
        make_zip(
            new_apkg,
            {
                "collection.anki21b": compressed.read_bytes(),
                "media": media_zstd.read_bytes(),
                "0": b"modern-audio",
            },
        )
        collection, media, _ = MODULE.prepare_collection(new_apkg, temp / "new")
        assert collection.read_bytes() == b"new-sqlite-bytes"
        assert (media / "modern.mp3").read_bytes() == b"modern-audio"

        binary_manifest = temp / "media-protobuf"
        binary_manifest_zstd = temp / "media-protobuf.zst"
        binary_manifest.write_bytes(b"\x0a\x03abc\x10\x01")
        subprocess.run(
            ["zstd", "-q", "-f", str(binary_manifest), "-o", str(binary_manifest_zstd)],
            check=True,
        )
        binary_apkg = temp / "modern-binary-media.apkg"
        make_zip(
            binary_apkg,
            {
                "collection.anki21b": compressed.read_bytes(),
                "media": binary_manifest_zstd.read_bytes(),
            },
        )
        collection, media, _ = MODULE.prepare_collection(binary_apkg, temp / "modern-binary")
        assert collection.read_bytes() == b"new-sqlite-bytes"
        assert list(media.iterdir()) == []

        unsafe_apkg = temp / "unsafe.apkg"
        make_zip(
            unsafe_apkg,
            {
                "collection.anki2": b"sqlite",
                "media": json.dumps({"0": "../escape"}).encode(),
                "0": b"private",
            },
        )
        try:
            MODULE.prepare_collection(unsafe_apkg, temp / "unsafe")
        except AssertionError as error:
            assert "unsafe APKG media filename" in str(error)
        else:
            raise AssertionError("unsafe media path was accepted")

    print("test_apkg_prepare: ok (legacy, modern, media safety)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
