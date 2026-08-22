#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SystemExit(f"FAIL: {message}")


def main() -> int:
    app_wrapper = (ROOT / "native/app.c").read_text(encoding="utf-8")
    platform = (ROOT / "native/app_platform.inc").read_text(encoding="utf-8")
    ime = (ROOT / "web/ime.js").read_text(encoding="utf-8")
    reviewer_html = (ROOT / "web/reviewer.html").read_text(encoding="utf-8")
    references = (ROOT / "docs/REFERENCE_IMPLEMENTATIONS.md").read_text(encoding="utf-8")
    workflow = (REPO / ".github/workflows/kindle-anki-port.yml").read_text(encoding="utf-8")

    require('#include "app_platform.inc"' in app_wrapper,
            "native host does not compose the Kindle platform adapter")
    for symbol in ("stop_audio", "load_decks", "dispatch_uri"):
        require(f"#define {symbol} app_part3_{symbol}" in app_wrapper,
                f"native host does not isolate platform wrapper {symbol}")
    require("KAP_WINDOW_TITLE" in app_wrapper,
            "native host does not override the generic GTK title")

    require('KAP_WINDOW_TITLE "L:A_N:application_ID:" KAP_APP_ID "_PC:N"' in platform,
            "Lab126/Awesome application window identity is missing")
    require('KAP_LIPC_SET_PROP "/usr/bin/lipc-set-prop"' in platform,
            "Kindle keyboard command is not pinned to lipc-set-prop")
    require('KAP_KEYBOARD_PUBLISHER "com.lab126.keyboard"' in platform,
            "Lab126 keyboard publisher is missing")
    require("execl(KAP_LIPC_SET_PROP" in platform,
            "keyboard adapter does not use a direct argument-vector exec")
    require("/bin/sh" not in platform and "system(" not in platform,
            "keyboard adapter must not invoke a shell")
    require("kap_wait_child_bounded" in platform and "kill(pid, SIGKILL)" in platform,
            "keyboard command lifecycle is not bounded and reaped")
    for operation in ("ime/open", "ime/close", "review/reveal", "app/back", "app/close"):
        require(f'kap_uri_operation_is(uri, "{operation}")' in platform,
                f"native platform adapter does not handle {operation}")

    require("document.addEventListener('focus', onFocus, true)" in ime,
            "typed-answer focus is not captured")
    require("document.addEventListener('blur', onBlur, true)" in ime,
            "typed-answer blur is not captured")
    require("originalSend('ime/open'" in ime and "originalSend('ime/close'" in ime,
            "web IME adapter does not emit the versioned native operations")
    require("operation === 'review/reveal'" in ime,
            "web IME adapter does not close before answer reveal")

    bridge_pos = reviewer_html.find("/bridge.js")
    ime_pos = reviewer_html.find("/ime.js")
    reviewer_pos = reviewer_html.find("/reviewer.js")
    require(0 <= bridge_pos < ime_pos < reviewer_pos,
            "reviewer must load bridge, IME adapter and reviewer in that order")

    for pin in (
        "d671ee657f0c411474d2afff3bf9cbb49be2fb44",
        "9f67dd04634d16dfa2e8eeef13eb582b8225e49e",
        "f8c260636dc4fa811c7e470b8b4626985a188172",
        "134d04e20d4eaa83a51369eaa80fd3fa007a4d46",
    ):
        require(pin in references, f"reference implementation pin {pin} is not documented")
    require("Ranki is not a production, build or packaging dependency" in references,
            "Ranki independence boundary is not documented")
    require("No Ranki, em-dash or Kindle Explorer source" in references,
            "clean-room adaptation record is missing")

    require("workflow_dispatch:" in workflow,
            "manual checkpoint trigger is missing")
    require("\n  push:" not in workflow and "\n  pull_request:" not in workflow,
            "GitHub Actions must remain manual-only while runner quota is unavailable")

    print("test_platform_reference_contract: ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
