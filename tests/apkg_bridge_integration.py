#!/usr/bin/env python3
"""Import pinned APKGs unchanged and render them through the production bridge."""

import ctypes
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


if len(sys.argv) != 7:
    raise SystemExit(
        f"usage: {sys.argv[0]} LIB SEEDER SCRATCH ROOT MANIFEST PACKET_OUTPUT"
    )

library_path = Path(sys.argv[1]).resolve()
seeder_path = Path(sys.argv[2]).resolve()
scratch_path = Path(sys.argv[3]).resolve()
root_path = Path(sys.argv[4]).resolve()
manifest_path = Path(sys.argv[5]).resolve()
packet_output_path = Path(sys.argv[6]).resolve()


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def load_manifest(path: Path):
    fixtures = []
    for line_number, raw_line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        require(match is not None, f"invalid fixture manifest line {line_number}")
        expected, relative = match.groups()
        package = (root_path / relative).resolve()
        require(package.is_relative_to(root_path), "fixture path escaped the repository")
        require(package.is_file(), f"fixture is missing: {relative}")
        require(package.suffix == ".apkg", f"fixture is not an APKG: {relative}")
        fixtures.append((expected, relative, package))
    require(len(fixtures) == 7, f"expected seven pinned APKG fixtures, found {len(fixtures)}")
    return fixtures


library = ctypes.CDLL(str(library_path))
library.kanki_string_free.argtypes = [ctypes.c_void_p]
library.kanki_string_free.restype = None
library.kanki_core_new.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
library.kanki_core_new.restype = ctypes.c_void_p
library.kanki_core_free.argtypes = [ctypes.c_void_p]
library.kanki_core_free.restype = None

SIGNATURES = {
    "kanki_open_collection_json": [
        ctypes.c_void_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
        ctypes.c_char_p,
    ],
    "kanki_close_collection_json": [ctypes.c_void_p],
    "kanki_deck_tree_json": [ctypes.c_void_p],
    "kanki_set_current_deck_json": [ctypes.c_void_p, ctypes.c_int64],
    "kanki_next_card_json": [ctypes.c_void_p],
    "kanki_prepare_answer_json": [ctypes.c_void_p, ctypes.c_char_p],
}
for function_name, argument_types in SIGNATURES.items():
    function = getattr(library, function_name)
    function.argtypes = argument_types
    function.restype = ctypes.c_void_p


def owned_json(label: str, function_name: str, *arguments):
    pointer = getattr(library, function_name)(*arguments)
    require(bool(pointer), f"{label} returned NULL")
    try:
        envelope = json.loads(ctypes.string_at(pointer).decode("utf-8"))
    finally:
        library.kanki_string_free(pointer)
    require(envelope.get("ok") is True, f"{label} failed: {envelope.get('error')}")
    return envelope.get("data")


def new_core() -> int:
    error_pointer = ctypes.c_void_p()
    core = library.kanki_core_new(ctypes.byref(error_pointer))
    if core:
        return core
    message = "unknown core initialization failure"
    if error_pointer.value:
        try:
            message = ctypes.string_at(error_pointer.value).decode("utf-8")
        finally:
            library.kanki_string_free(error_pointer.value)
    raise AssertionError(message)


def nodes(node):
    for child in node.get("children", []):
        yield from nodes(child)
    yield node


def queued_count(node) -> int:
    counts = node.get("counts", {})
    return sum(int(counts.get(kind, 0)) for kind in ("new", "learning", "review"))


fixtures = load_manifest(manifest_path)
scratch_path.mkdir(parents=True, exist_ok=True)
packets = []
summaries = []

for index, (expected_hash, relative_path, package_path) in enumerate(fixtures):
    actual_hash = sha256_file(package_path)
    require(actual_hash == expected_hash, f"fixture checksum changed: {relative_path}")

    fixture_root = scratch_path / f"{index:02d}-{package_path.stem}"
    media_path = fixture_root / "media"
    collection_path = fixture_root / "collection.anki2"
    media_db_path = fixture_root / "media.db2"
    fixture_root.mkdir(parents=True)
    imported = subprocess.run(
        [
            str(seeder_path),
            str(collection_path),
            str(media_path),
            str(media_db_path),
            str(package_path),
        ],
        check=True,
        capture_output=True,
        text=True,
    )
    match = re.fullmatch(r"found_notes=(\d+)\n?", imported.stdout)
    require(match is not None, f"unexpected seeder output for {relative_path}")
    found_notes = int(match.group(1))
    require(found_notes > 0, f"backend imported no notes from {relative_path}")

    core = new_core()
    opened = False
    try:
        owned_json(
            "open",
            "kanki_open_collection_json",
            core,
            str(collection_path).encode(),
            str(media_path).encode(),
            str(media_db_path).encode(),
        )
        opened = True
        tree = owned_json("decks", "kanki_deck_tree_json", core)
        eligible_decks = [
            deck for deck in nodes(tree) if int(deck.get("id", 0)) > 0 and queued_count(deck) > 0
        ]
        require(eligible_decks, f"no queued deck after importing {relative_path}")
        deck = eligible_decks[0]
        owned_json(
            "select",
            "kanki_set_current_deck_json",
            core,
            int(deck["id"]),
        )
        card = owned_json("next", "kanki_next_card_json", core)
        require(card.get("finished") is False, f"no card rendered from {relative_path}")
        require(int(card.get("card_id", 0)) > 0, "render packet lost its card ID")
        require(int(card.get("template_ordinal", -1)) >= 0, "template ordinal is missing")
        question_html = card.get("question_html")
        answer_html = card.get("answer_html")
        css = card.get("css")
        require(isinstance(question_html, str) and question_html.strip(), "question is empty")
        require(isinstance(answer_html, str) and answer_html.strip(), "answer is empty")
        require(isinstance(css, str), "note type CSS is not a string")
        require(isinstance(card.get("question_audio"), list), "question AV is not typed")
        require(isinstance(card.get("answer_audio"), list), "answer AV is not typed")
        require(card.get("intervals"), "scheduler intervals are missing")

        prepared = owned_json(
            "prepare",
            "kanki_prepare_answer_json",
            core,
            b"",
        )
        require(isinstance(prepared.get("html"), str), "prepared answer HTML is missing")
        require(isinstance(prepared.get("audio"), list), "prepared answer AV is not typed")
        require(
            isinstance(prepared.get("question_audio"), list),
            "prepared question AV is not typed",
        )

        packets.append(
            {
                "fixture": package_path.name,
                "next_card": card,
                "prepared_answer": prepared,
            }
        )
        media_files = sorted(path.name for path in media_path.iterdir() if path.is_file())
        if package_path.name == "media.apkg":
            require(media_files == ["foo.wav"], "media.apkg did not import foo.wav unchanged")
        summaries.append(
            {
                "fixture": package_path.name,
                "sha256": actual_hash,
                "found_notes": found_notes,
                "deck_count": sum(1 for _ in nodes(tree)),
                "question_bytes": len(question_html.encode("utf-8")),
                "question_sha256": sha256_text(question_html),
                "answer_bytes": len(answer_html.encode("utf-8")),
                "answer_sha256": sha256_text(answer_html),
                "css_bytes": len(css.encode("utf-8")),
                "css_sha256": sha256_text(css),
                "question_av": len(card["question_audio"]),
                "answer_av": len(card["answer_audio"]),
                "type_answer": bool(card.get("type_answer")),
                "media_files": len(media_files),
            }
        )
        owned_json("close", "kanki_close_collection_json", core)
        opened = False
    finally:
        if opened:
            try:
                owned_json("close_after_failure", "kanki_close_collection_json", core)
            except Exception:
                pass
        library.kanki_core_free(core)

    require(
        sha256_file(package_path) == expected_hash,
        f"source APKG was modified while testing: {relative_path}",
    )

packet_output_path.parent.mkdir(parents=True, exist_ok=True)
packet_output_path.write_text(
    json.dumps({"fixtures": packets}, ensure_ascii=False, sort_keys=True, indent=2) + "\n",
    encoding="utf-8",
)
for summary in summaries:
    print("apkg_fixture=" + json.dumps(summary, sort_keys=True, separators=(",", ":")))
print(f"apkg_packets={packet_output_path}")
print("APKG bridge integration: pass")
