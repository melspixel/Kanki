#!/usr/bin/env python3
from __future__ import annotations

import argparse
import ctypes
import json
import subprocess
import tempfile
import zipfile
from pathlib import Path, PurePosixPath
from typing import Any


class KapLibrary:
    def __init__(self, path: Path) -> None:
        self.lib = ctypes.CDLL(str(path))
        self.lib.kap_string_free.argtypes = [ctypes.c_void_p]
        self.lib.kap_string_free.restype = None
        self.lib.kap_core_new.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
        self.lib.kap_core_new.restype = ctypes.c_void_p
        self.lib.kap_core_free.argtypes = [ctypes.c_void_p]
        self.lib.kap_core_free.restype = None

        for name in (
            "kap_build_info_json",
            "kap_close_collection_json",
            "kap_deck_tree_json",
            "kap_next_question_json",
            "kap_bury_current_json",
            "kap_health_json",
        ):
            fn = getattr(self.lib, name)
            fn.restype = ctypes.c_void_p
        self.lib.kap_open_collection_json.argtypes = [
            ctypes.c_void_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
            ctypes.c_char_p,
        ]
        self.lib.kap_open_collection_json.restype = ctypes.c_void_p
        self.lib.kap_set_current_deck_json.argtypes = [ctypes.c_void_p, ctypes.c_int64]
        self.lib.kap_set_current_deck_json.restype = ctypes.c_void_p
        self.lib.kap_reveal_answer_json.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        self.lib.kap_reveal_answer_json.restype = ctypes.c_void_p
        self.lib.kap_answer_json.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
        self.lib.kap_answer_json.restype = ctypes.c_void_p

    def read_json_ptr(self, ptr: int | None) -> dict[str, Any]:
        if not ptr:
            raise AssertionError("C ABI returned NULL instead of a JSON envelope")
        try:
            return json.loads(ctypes.string_at(ptr).decode("utf-8"))
        finally:
            self.lib.kap_string_free(ptr)

    def call(self, name: str, *args: Any) -> Any:
        envelope = self.read_json_ptr(getattr(self.lib, name)(*args))
        if not envelope.get("ok"):
            raise AssertionError(f"{name} failed: {envelope.get('error')}")
        return envelope.get("data")

    def new_core(self) -> int:
        error = ctypes.c_void_p()
        core = self.lib.kap_core_new(ctypes.byref(error))
        if not core:
            message = "unknown initialization error"
            if error.value:
                try:
                    message = ctypes.string_at(error.value).decode("utf-8", "replace")
                finally:
                    self.lib.kap_string_free(error.value)
            raise AssertionError(message)
        return int(core)


def safe_media_filename(value: str) -> bool:
    path = PurePosixPath(value)
    return bool(value) and not path.is_absolute() and ".." not in path.parts and "\\" not in value


def prepare_collection(apkg: Path, destination: Path) -> tuple[Path, Path, Path]:
    """Extract a real APKG into the collection/media layout expected by rslib.

    Current Anki packages store a zstd-compressed ``collection.anki21b`` while
    older, still-valid packages contain a plain ``collection.anki2``.  Release
    integration coverage deliberately accepts both formats so it can exercise
    real-world decks instead of only packages exported by the newest desktop.
    """
    media = destination / "collection.media"
    media.mkdir(parents=True)
    compressed = destination / "collection.anki21b"
    collection = destination / "collection.anki2"
    with zipfile.ZipFile(apkg) as archive:
        names = set(archive.namelist())
        if "collection.anki21b" in names:
            compressed.write_bytes(archive.read("collection.anki21b"))
            subprocess.run(
                ["zstd", "-q", "-d", "-f", str(compressed), "-o", str(collection)],
                check=True,
            )
        elif "collection.anki2" in names:
            collection.write_bytes(archive.read("collection.anki2"))
        elif "collection.anki21" in names:
            collection.write_bytes(archive.read("collection.anki21"))
        else:
            raise AssertionError(f"APKG has no supported collection payload: {apkg.name}")

        if "media" in names:
            media_manifest = archive.read("media")
            modern_binary_manifest = media_manifest.startswith(b"\x28\xb5\x2f\xfd")
            if modern_binary_manifest:
                media_manifest = subprocess.run(
                    ["zstd", "-q", "-d", "-c"],
                    input=media_manifest,
                    check=True,
                    capture_output=True,
                ).stdout
            # Legacy APKGs use a JSON index mapping numeric members to media
            # names. Current packages may use Anki's zstd-compressed protobuf
            # media manifest instead; rslib owns that format, and this reviewer
            # lifecycle test does not need to duplicate its parser. Extract
            # media when the manifest is JSON, otherwise leave the temporary
            # media directory empty while still exercising the real AV tags.
            try:
                mapping = json.loads(media_manifest.decode("utf-8"))
            except (UnicodeDecodeError, json.JSONDecodeError):
                if not modern_binary_manifest:
                    raise AssertionError(f"invalid legacy APKG media map: {apkg.name}")
                mapping = {}
            if not isinstance(mapping, dict):
                raise AssertionError(f"APKG media map is not an object: {apkg.name}")
            for member, filename in mapping.items():
                if member not in names:
                    continue
                if not isinstance(filename, str) or not safe_media_filename(filename):
                    raise AssertionError(f"unsafe APKG media filename: {filename!r}")
                target = media / filename
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(archive.read(member))
    return collection, media, destination / "media.db2"


def total_count(deck: dict[str, Any]) -> int:
    counts = deck.get("counts") or {}
    return int(counts.get("new", 0)) + int(counts.get("learning", 0)) + int(counts.get("review", 0))


def find_study_deck(deck: dict[str, Any]) -> dict[str, Any] | None:
    for child in deck.get("children") or []:
        found = find_study_deck(child)
        if found:
            return found
    return deck if total_count(deck) > 0 and int(deck.get("id", 0)) != 0 else None


def exercise(lib: KapLibrary, apkg: Path, require_typed: bool, max_cards: int) -> dict[str, Any]:
    with tempfile.TemporaryDirectory(prefix="kap-core-integration-") as temp_text:
        temp = Path(temp_text)
        collection, media, media_db = prepare_collection(apkg, temp)
        core = lib.new_core()
        observed = {
            "question": False,
            "answer": False,
            "typed": False,
            "audio": False,
            "rated": False,
            "buried": 0,
            "duplicate_next_rejected": False,
        }
        try:
            info = lib.call("kap_build_info_json")
            assert info["source_driven_port"] is True
            assert int(info["abi_version"]) == 1

            opened = lib.call(
                "kap_open_collection_json",
                core,
                str(collection).encode(),
                str(media).encode(),
                str(media_db).encode(),
            )
            assert opened["opened"] is True
            tree = lib.call("kap_deck_tree_json", core)
            deck = find_study_deck(tree)
            if not deck:
                raise AssertionError(f"fixture has no study deck with queued counts: {apkg.name}")
            lib.call("kap_set_current_deck_json", core, int(deck["id"]))

            for _ in range(max_cards):
                packet = lib.call("kap_next_question_json", core)
                if packet["kind"] == "finished":
                    break
                assert packet["kind"] == "question"
                assert packet["card_id"]
                assert isinstance(packet.get("html"), str)
                assert isinstance(packet.get("css"), str)
                assert str(packet.get("body_class", "")).startswith("card card")
                observed["question"] = True
                observed["audio"] = observed["audio"] or bool(packet.get("audio"))
                is_typed = bool((packet.get("typed") or {}).get("enabled"))
                observed["typed"] = observed["typed"] or is_typed

                duplicate = lib.read_json_ptr(lib.lib.kap_next_question_json(core))
                assert duplicate.get("ok") is False, duplicate
                assert "rated or buried" in str(duplicate.get("error", "")), duplicate
                observed["duplicate_next_rejected"] = True

                if is_typed or not observed["answer"]:
                    answer = lib.call("kap_reveal_answer_json", core, b"")
                    assert answer["kind"] == "answer"
                    assert answer["card_id"] == packet["card_id"]
                    assert isinstance(answer.get("html"), str)
                    observed["answer"] = True
                    action = lib.call("kap_answer_json", core, 3, 25)
                    assert action["action"] == "rated"
                    assert int(action["rating"]) == 3
                    observed["rated"] = True
                    if is_typed:
                        break
                else:
                    action = lib.call("kap_bury_current_json", core)
                    assert action["action"] == "buried"
                    observed["buried"] += 1

            health = lib.call("kap_health_json", core)
            assert health["backend"] == "responsive"
            closed = lib.call("kap_close_collection_json", core)
            assert closed["closed"] is True
        finally:
            lib.lib.kap_core_free(core)

        if not observed["question"] or not observed["answer"] or not observed["rated"]:
            raise AssertionError(f"review lifecycle was not exercised: {observed}")
        if not observed["duplicate_next_rejected"]:
            raise AssertionError(f"active-card next-question guard was not exercised: {observed}")
        if require_typed and not observed["typed"]:
            raise AssertionError(f"no typed-answer card found within {max_cards} cards: {observed}")
        return observed


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--library", type=Path, required=True)
    parser.add_argument("--apkg", type=Path, action="append", required=True)
    parser.add_argument("--typed-apkg", type=Path)
    parser.add_argument("--max-cards", type=int, default=64)
    args = parser.parse_args()

    lib = KapLibrary(args.library)
    reports: dict[str, Any] = {}
    for apkg in args.apkg:
        reports[apkg.name] = exercise(lib, apkg, False, args.max_cards)
    if args.typed_apkg:
        reports[args.typed_apkg.name] = exercise(lib, args.typed_apkg, True, args.max_cards)
    print(json.dumps(reports, ensure_ascii=False, sort_keys=True))
    print("test_core_integration: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
