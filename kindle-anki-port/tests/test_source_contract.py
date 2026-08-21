#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def exported_c_functions(header: str) -> set[str]:
    return set(re.findall(r"\b(kap_[a-z0-9_]+)\s*\(", header))


def rust_exports(source: str) -> set[str]:
    return set(
        re.findall(
            r"#\[no_mangle\]\s*pub\s+extern\s+\"C\"\s+fn\s+(kap_[a-z0-9_]+)\s*\(",
            source,
        )
    )


def main() -> int:
    header = (ROOT / "core" / "kap_core.h").read_text(encoding="utf-8")
    port = (ROOT / "core" / "src" / "port.rs").read_text(encoding="utf-8")
    bridge = (ROOT / "core" / "src" / "services_bridge.rs").read_text(encoding="utf-8")
    app = (ROOT / "native" / "app.c").read_text(encoding="utf-8")
    sync = (ROOT / "native" / "sync.c").read_text(encoding="utf-8")
    reviewer_html = (ROOT / "web" / "reviewer.html").read_text(encoding="utf-8")
    reviewer_js = (ROOT / "web" / "reviewer.js").read_text(encoding="utf-8")

    declared = exported_c_functions(header)
    implemented = rust_exports(port)
    require(declared == implemented, f"C ABI mismatch: declared={sorted(declared)} implemented={sorted(implemented)}")

    runtime_resolvers = app + "\n" + sync
    for symbol in sorted(declared):
        require(f'"{symbol}"' in runtime_resolvers or symbol in {"kap_string_free", "kap_build_info_json"},
                f"native programs do not resolve {symbol}")

    required_bridge = {
        "open_collection",
        "close_collection",
        "latest_progress",
        "deck_tree",
        "set_current_deck",
        "set_deck_collapsed",
        "get_note",
        "get_notetype",
        "extract_av_tags",
        "render_existing_card",
        "compare_answer",
        "extract_cloze_for_typing",
        "get_queued_cards",
        "describe_next_states",
        "answer_card",
        "bury_or_suspend_cards",
        "sync_collection",
        "full_upload_or_download",
        "media_sync_status",
        "abort_sync",
        "abort_media_sync",
    }
    bridge_functions = set(re.findall(r"pub\(crate\)\s+fn\s+([a-z0-9_]+)\s*\(", bridge))
    require(required_bridge <= bridge_functions, f"semantic bridge missing {sorted(required_bridge - bridge_functions)}")
    require("BackendCollectionService" in bridge, "generated collection trait is not imported in bridge")

    require("crate::services::kap_bridge" in port, "semantic port bypasses the bridge module")
    require("run_backend_" not in port, "port must not call generated numeric dispatch")
    require("anki_backend_command" not in port, "port must not expose generic numeric backend calls")

    require(reviewer_html.count('id="qa"') == 1, "reviewer must have exactly one persistent #qa root")
    require("qa.innerHTML" in reviewer_js, "reviewer does not update the persistent #qa root")
    require("replaceChild(replacement" in reviewer_js, "inserted card scripts are not re-executed")
    require("kap-type-answer-slot" in reviewer_js, "typed-answer input slot is not implemented")
    require("window.scrollBy" in reviewer_js, "e-ink page navigation is not implemented")
    require("webkit_web_view_get_pixel_density" in app,
            "native host does not query Kindle pixel density")
    require("webkit_web_view_set_full_content_zoom" in app,
            "native host does not require full-content zoom")
    require("prepare_webkit_global(app);" in app,
            "W3C CSS pixels must be enabled before WebView creation")

    runtime_files = [
        ROOT / "core" / "src" / "port.rs",
        ROOT / "core" / "src" / "services_bridge.rs",
        ROOT / "native" / "app.c",
        ROOT / "native" / "audio.c",
        ROOT / "native" / "sync.c",
        *sorted((ROOT / "web").glob("*")),
        *sorted((ROOT / "scripts").glob("*")),
    ]
    forbidden = ["COCA-English", "4000 Essential", "rewrite-v1", "LD_PRELOAD"]
    runtime_text = "\n".join(path.read_text(encoding="utf-8", errors="replace") for path in runtime_files if path.is_file())
    for token in forbidden:
        require(token not in runtime_text, f"runtime contains forbidden legacy/card-specific token {token!r}")

    print("test_source_contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
