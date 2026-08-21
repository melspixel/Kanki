#!/usr/bin/env python3
"""Exercise the production semantic C ABI against a disposable Anki collection."""

import ctypes
import json
import re
import sqlite3
import sys
from pathlib import Path


def require(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


if len(sys.argv) != 5:
    raise SystemExit(f"usage: {sys.argv[0]} LIB COLLECTION MEDIA MEDIA_DB")

library_path, collection_path, media_path, media_db_path = map(Path, sys.argv[1:])
library = ctypes.CDLL(str(library_path.resolve()))
library.kanki_string_free.argtypes = [ctypes.c_void_p]
library.kanki_string_free.restype = None
library.kanki_core_new.argtypes = [ctypes.POINTER(ctypes.c_void_p)]
library.kanki_core_new.restype = ctypes.c_void_p
library.kanki_core_free.argtypes = [ctypes.c_void_p]
library.kanki_core_free.restype = None

SIGNATURES = {
    "kanki_open_collection_json": [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p, ctypes.c_char_p],
    "kanki_close_collection_json": [ctypes.c_void_p],
    "kanki_deck_tree_json": [ctypes.c_void_p],
    "kanki_health_json": [ctypes.c_void_p],
    "kanki_next_card_json": [ctypes.c_void_p],
    "kanki_prepare_answer_json": [ctypes.c_void_p, ctypes.c_char_p],
    "kanki_answer_json": [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32],
    "kanki_bury_current_json": [ctypes.c_void_p],
}
for function_name, argument_types in SIGNATURES.items():
    function = getattr(library, function_name)
    function.argtypes = argument_types
    function.restype = ctypes.c_void_p


def owned_json(label: str, function_name: str, *arguments):
    pointer = getattr(library, function_name)(*arguments)
    require(bool(pointer), f"{label} returned NULL")
    try:
        text = ctypes.string_at(pointer).decode("utf-8")
    finally:
        library.kanki_string_free(pointer)
    envelope = json.loads(text)
    require(envelope.get("ok") is True, f"{label} failed: {envelope.get('error')}")
    print(f"{label}={json.dumps(envelope, ensure_ascii=True, separators=(',', ':'))}")
    return envelope.get("data")


def new_core() -> int:
    error_pointer = ctypes.c_void_p()
    core = library.kanki_core_new(ctypes.byref(error_pointer))
    if not core:
        message = "unknown core initialization failure"
        if error_pointer.value:
            try:
                message = ctypes.string_at(error_pointer.value).decode("utf-8")
            finally:
                library.kanki_string_free(error_pointer.value)
        raise AssertionError(message)
    return core


def open_collection(core: int, label: str = "integration_open"):
    return owned_json(
        label,
        "kanki_open_collection_json",
        core,
        str(collection_path).encode(),
        str(media_path).encode(),
        str(media_db_path).encode(),
    )


def sound_sources(tags):
    return [tag.get("source") for tag in tags if tag.get("kind") == "sound"]


core = new_core()
answered = {}
buried_card_id = None
try:
    open_collection(core)
    tree = owned_json("integration_decks", "kanki_deck_tree_json", core)
    require(tree["children"][0]["counts"]["new"] == 5, "fixture must expose five new cards")

    for rating in range(1, 5):
        card = owned_json(f"queue_{rating}", "kanki_next_card_json", core)
        require(card.get("finished") is False, f"rating {rating} had no queued card")
        card_id = int(card["card_id"])
        require(card_id not in answered, "scheduler returned an already answered fixture card")
        require(card.get("type_answer") is True, "typed-answer semantic was not prepared")
        require(card.get("autoplay") is True, "default deck autoplay semantic was lost")
        require(
            card.get("replay_question_audio_on_answer_side") is True,
            "default answer-side question replay semantic was lost",
        )
        require(len(card.get("intervals", [])) == 4, "backend must provide four rating intervals")
        require("id=\"typeans\"" in card.get("question_html", ""), "question input missing")
        require("[anki:play:q:0]" in card.get("question_html", ""), "question AV marker missing")
        question_sources = sound_sources(card.get("question_audio", []))
        answer_sources = sound_sources(card.get("answer_audio", []))
        require(len(question_sources) == 1 and len(answer_sources) == 1, "sound AV extraction failed")
        require(
            any(tag.get("kind") == "tts" for tag in card.get("question_audio", [])),
            "question TTS extraction failed",
        )
        require(
            any(tag.get("kind") == "tts" for tag in card.get("answer_audio", [])),
            "answer TTS extraction failed",
        )
        match = re.fullmatch(r"q([1-5])\.mp3", question_sources[0])
        require(match is not None, f"unexpected question source: {question_sources[0]}")
        fixture_index = int(match.group(1))
        require(answer_sources == [f"a{fixture_index}.mp3"], "question/answer AV pairing changed")

        prepared = owned_json(
            f"prepare_{rating}",
            "kanki_prepare_answer_json",
            core,
            f"Answer {fixture_index}".encode(),
        )
        require("<hr id=answer>" in prepared["html"], "answer separator placement changed")
        require("class=typeGood" in prepared["html"], "typed answer did not compare as correct")
        require("[anki:play:q:0]" in prepared["html"], "FrontSide question AV marker changed")
        require("[anki:play:a:0]" in prepared["html"], "answer AV marker missing")
        require(sound_sources(prepared["question_audio"]) == question_sources, "question AV lost")
        require(sound_sources(prepared["audio"]) == answer_sources, "answer AV lost")
        require(prepared.get("autoplay") is True, "prepared answer autoplay semantic changed")
        require(
            prepared.get("replay_question_audio_on_answer_side") is True,
            "prepared answer replay semantic changed",
        )

        result = owned_json(
            f"answer_{rating}", "kanki_answer_json", core, rating, 1234 + rating
        )
        require(int(result["card_id"]) == card_id, "answer targeted the wrong card")
        require(int(result["rating"]) == rating, "answer rating changed across the bridge")
        answered[card_id] = rating

    card = owned_json("queue_bury", "kanki_next_card_json", core)
    require(card.get("finished") is False, "fixture had no card left to bury")
    buried_card_id = int(card["card_id"])
    buried = owned_json("bury", "kanki_bury_current_json", core)
    require(buried.get("buried") is True, "bury semantic did not report success")
    require(int(buried["card_id"]) == buried_card_id, "bury targeted the wrong card")
    owned_json("integration_close", "kanki_close_collection_json", core)
finally:
    library.kanki_core_free(core)

with sqlite3.connect(collection_path) as database:
    revlog = database.execute("select cid, ease from revlog order by id").fetchall()
    buried_count = database.execute(
        # Pinned Anki distinguishes sibling/scheduler burial (-2) from the
        # explicit user burial requested by Kanki (-3).
        "select count(*) from cards where id = ? and queue = -3", (buried_card_id,)
    ).fetchone()[0]
require(len(revlog) == 4, f"expected four revlog entries, found {len(revlog)}")
require({int(card_id): int(ease) for card_id, ease in revlog} == answered, "revlog ratings differ")
require(buried_count == 1, "buried card was not persisted with the user-buried queue")
print(f"persistence={json.dumps({'revlog': len(revlog), 'buried': buried_count}, separators=(',', ':'))}")

reopen_core = new_core()
try:
    open_collection(reopen_core, "reopen")
    owned_json("reopen_health", "kanki_health_json", reopen_core)
    owned_json("reopen_close", "kanki_close_collection_json", reopen_core)
finally:
    library.kanki_core_free(reopen_core)

print("anki bridge integration: pass")
