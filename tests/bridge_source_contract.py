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

# A future autoplay fix must be based on effective deck-config semantics. Keep
# the expected upstream field names in this contract once the DTO lands; until
# then this test deliberately does not claim that autoplay parity is closed.

print("typed bridge source contract: pass")
