#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "bridge/anki_bridge.rs").read_text(encoding="utf-8")


def require(fragment: str, message: str) -> None:
    if fragment not in SOURCE:
        raise SystemExit(message)


def forbid(fragment: str, message: str) -> None:
    if fragment in SOURCE:
        raise SystemExit(message)


# Desktop Anki removes <hr id=answer> temporarily, then reinserts it at the
# [[type:...]] comparison marker. A previous design review suspected the bridge
# prepended it to the whole answer, so keep the source contract explicit.
require(
    'replacement.push_str("<hr id=answer>");',
    "typed-answer separator must be placed in the marker replacement",
)
require(
    'let html = replace_type_markers(&without_separator, &replacement);',
    "typed-answer comparison must replace the type marker in-place",
)
forbid(
    'format!("<hr id=answer>{html}")',
    "typed-answer separator must not be prepended to the full answer document",
)
forbid(
    'format!("<hr id=answer>{answer}")',
    "typed-answer separator must not be prepended to the full answer document",
)

# Scheduling must remain typed/semantic rather than reintroducing opaque
# service/method dispatch numbers.
forbid("service_index", "numeric service dispatch is forbidden in the typed bridge")
forbid("method_index", "numeric method dispatch is forbidden in the typed bridge")
require("SchedulerService::get_queued_cards", "typed scheduler queue call is missing")
require("SchedulerService::answer_card", "typed answer call is missing")
require("CardRenderingService::render_existing_card", "typed card rendering call is missing")
require("CardRenderingService::extract_av_tags", "typed AV extraction call is missing")

# The bridge is compiled inside the pinned Anki rslib, so it must use the
# generated traits exposed by that crate and preserve the source-owned C ABI
# consumed by both the native device shell and the safe host client.
require("use crate::services::{", "bridge must use pinned Anki service traits")
forbid(
    "use anki_proto_gen::services",
    "bridge must not import service traits from the proto generator crate",
)
require(
    "pub extern \"C\" fn kanki_string_free",
    "semantic ABI string destructor is missing",
)
require(
    "pub extern \"C\" fn kanki_core_new(error_out: *mut *mut c_char)",
    "semantic ABI core constructor signature drifted",
)
require(
    "media_db_path: *const c_char",
    "collection ABI must include the media database path",
)
require(
    "pub extern \"C\" fn kanki_next_card_json(core: *mut KankiCore)",
    "next-card ABI signature drifted",
)
require("pub extern \"C\" fn kanki_health_json", "semantic ABI health check is missing")

# FrontSide must be expanded only after question AV extraction, matching the
# desktop pipeline. Standard filters remain owned by Anki; any add-on filter
# replacement is rejected instead of being emulated by the bridge.
require("partial_render: true", "reviewer render must retain the FrontSide node")
require("fn render_template_text(", "render-node contract must be checked")
require(
    'replacement.field_name == "FrontSide"',
    "only Anki's semantic FrontSide replacement may be completed by Kanki",
)
require(
    "Some(&question_html)",
    "answer rendering must use question HTML after question AV extraction",
)
forbid(
    "out.push_str(&replacement.current_text)",
    "bridge must not emulate Anki partial-template replacement",
)

# Desktop reviewer semantics copy the queued card's custom data into the
# current state before answering, map UI ease 1..=4 to proto rating 0..=3, and
# record a real answer timestamp.
require(
    "current.custom_data = Some(card.custom_data.clone());",
    "queued card custom data must be preserved for scheduler answers",
)
require(
    "1 => (card_answer::Rating::Again",
    "Again must map to the typed Anki rating enum",
)
require(
    "4 => (card_answer::Rating::Easy",
    "Easy must map to the typed Anki rating enum",
)
forbid("rating: rating as i32", "UI rating must not be cast directly to the proto enum")
require("answered_at_millis: now_millis()", "scheduler answer timestamp must be real")

# Playback flags must be derived from the effective Anki deck config, including
# the original deck for cards currently in a filtered deck.
require("card.original_deck_id", "filtered-card playback must use its original deck")
require("!config.disable_autoplay", "autoplay must come from the Anki deck config")
require(
    "!config.skip_question_when_replaying_answer",
    "answer-side question replay must come from the Anki deck config",
)

print("typed bridge source contract: pass")
