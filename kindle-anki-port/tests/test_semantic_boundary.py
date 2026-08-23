#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PORT = (ROOT / "core/src/port.rs").read_text(encoding="utf-8")
BRIDGE = (ROOT / "core/src/services_bridge.rs").read_text(encoding="utf-8")
HEADER = (ROOT / "core/kap_core.h").read_text(encoding="utf-8")

EXPECTED_BRIDGE = {
    "open_collection", "close_collection", "upgrade_scheduler", "latest_progress", "deck_tree",
    "set_current_deck", "set_deck_collapsed", "get_note", "get_notetype",
    "extract_av_tags", "render_existing_card",
    "compare_answer", "extract_cloze_for_typing", "get_queued_cards",
    "describe_next_states", "answer_card", "bury_or_suspend_cards",
        "sync_collection", "full_upload_or_download", "media_sync_status",
        "abort_sync", "abort_media_sync",
}
EXPECTED_ABI = {
    "kap_build_info_json", "kap_core_new", "kap_core_free",
    "kap_open_collection_json", "kap_close_collection_json",
    "kap_deck_tree_json", "kap_set_current_deck_json",
    "kap_set_deck_collapsed_json", "kap_next_question_json",
    "kap_reveal_answer_json", "kap_answer_json", "kap_bury_current_json",
    "kap_sync_collection_json", "kap_full_sync_json",
        "kap_media_sync_status_json", "kap_abort_sync_json",
        "kap_health_json", "kap_string_free",
}


def main() -> int:
    assert "use crate::services::kap_bridge;" in PORT
    assert "BackendCardRenderingService" not in PORT
    assert "BackendSchedulerService" not in PORT
    assert "BackendDecksService" not in PORT
    assert "BackendNotesService" not in PORT

    bridge_functions = set(re.findall(r"pub\(crate\) fn\s+([A-Za-z0-9_]+)", BRIDGE))
    assert EXPECTED_BRIDGE <= bridge_functions, EXPECTED_BRIDGE - bridge_functions
    assert not re.search(r"(?m)^pub fn\s+", BRIDGE), "bridge must remain crate-internal"
    for name in EXPECTED_BRIDGE:
        assert f"kap_bridge::{name}" in PORT, name

    rust_exports = set(re.findall(r'pub extern "C" fn\s+([A-Za-z0-9_]+)', PORT))
    header_exports = set(re.findall(r"\b(kap_[A-Za-z0-9_]+)\s*\(", HEADER))
    assert EXPECTED_ABI <= rust_exports
    assert EXPECTED_ABI <= header_exports
    assert rust_exports == header_exports, (rust_exports - header_exports, header_exports - rust_exports)

    forbidden_products = [
        "COCA-English", "4000 Essential English Words", "百词斩", "新东方雅思",
        "Advanced Vocabulary Complete",
    ]
    joined = "\n".join(
        path.read_text(encoding="utf-8", errors="replace")
        for path in [ROOT / "core/src/port.rs", ROOT / "native/app.c",
                     ROOT / "web/reviewer.js", ROOT / "web/platform.css"]
    )
    for product in forbidden_products:
        assert product not in joined

    print("test_semantic_boundary: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
