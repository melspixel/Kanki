#!/usr/bin/env python3
from __future__ import annotations

import argparse
import re
from pathlib import Path

EXPECTED = {
    "open_collection": "Result<()>",
    "close_collection": "Result<()>",
    "latest_progress": "Result<anki_proto::collection::Progress>",
    "deck_tree": "Result<anki_proto::decks::DeckTreeNode>",
    "set_current_deck": "Result<anki_proto::collection::OpChanges>",
    "set_deck_collapsed": "Result<anki_proto::collection::OpChanges>",
    "get_note": "Result<anki_proto::notes::Note>",
    "get_notetype": "Result<anki_proto::notetypes::Notetype>",
    "extract_av_tags": "Result<anki_proto::card_rendering::ExtractAvTagsResponse>",
    "render_existing_card": "Result<anki_proto::card_rendering::RenderCardResponse>",
    "compare_answer": "Result<anki_proto::generic::String>",
    "extract_cloze_for_typing": "Result<anki_proto::generic::String>",
    "get_queued_cards": "Result<anki_proto::scheduler::QueuedCards>",
    "describe_next_states": "Result<anki_proto::generic::StringList>",
    "answer_card": "Result<anki_proto::collection::OpChanges>",
    "bury_or_suspend_cards": "Result<anki_proto::collection::OpChangesWithCount>",
}
SYNC_TRAIT = {
    "sync_collection": "Result<anki_proto::sync::SyncCollectionResponse>",
    "full_upload_or_download": "Result<()>",
    "media_sync_status": "Result<anki_proto::sync::MediaSyncStatusResponse>",
    "abort_sync": "Result<()>",
    "abort_media_sync": "Result<()>",
}


def normalize(value: str) -> str:
    return re.sub(r"\s+", "", value)


def signatures(text: str, name: str) -> list[str]:
    expression = re.compile(
        rf"fn\s+{re.escape(name)}\s*\([^)]*\)\s*->\s*([^{{;]+)", re.S
    )
    return [match.group(1).strip() for match in expression.finditer(text)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("generated_backend", type=Path)
    args = parser.parse_args()
    text = args.generated_backend.read_text(encoding="utf-8")
    errors: list[str] = []
    for name, expected in {**EXPECTED, **SYNC_TRAIT}.items():
        found = signatures(text, name)
        if not found:
            errors.append(f"missing generated method: {name}")
            continue
        if normalize(expected) not in {normalize(value) for value in found}:
            errors.append(f"signature mismatch {name}: expected {expected}, found {found}")
    if "pub trait BackendSyncService" not in text:
        errors.append("BackendSyncService trait missing")
    if errors:
        for error in errors:
            print(f"ERROR: {error}")
        return 1
    print(f"audit_generated_services: ok methods={len(EXPECTED) + len(SYNC_TRAIT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
