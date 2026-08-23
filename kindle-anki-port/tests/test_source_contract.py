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


def native_host_source() -> tuple[str, list[Path]]:
    wrapper = ROOT / "native" / "app.c"
    fragments = sorted((ROOT / "native").glob("app_part*.inc"))
    require(wrapper.is_file(), "native/app.c is missing")
    require(len(fragments) == 4, f"expected four native host fragments, found {len(fragments)}")
    text = "\n".join(
        [wrapper.read_text(encoding="utf-8")]
        + [path.read_text(encoding="utf-8") for path in fragments]
    )
    for fragment in fragments:
        require(f'#include "{fragment.name}"' in wrapper.read_text(encoding="utf-8"),
                f"native/app.c does not include {fragment.name}")
    return text, [wrapper, *fragments]


def main() -> int:
    header = (ROOT / "core" / "kap_core.h").read_text(encoding="utf-8")
    port = (ROOT / "core" / "src" / "port.rs").read_text(encoding="utf-8")
    bridge = (ROOT / "core" / "src" / "services_bridge.rs").read_text(encoding="utf-8")
    app, app_files = native_host_source()
    sync = (ROOT / "native" / "sync.c").read_text(encoding="utf-8")
    reviewer_html = (ROOT / "web" / "reviewer.html").read_text(encoding="utf-8")
    reviewer_js = (ROOT / "web" / "reviewer.js").read_text(encoding="utf-8")
    armhf_gates = (ROOT / "testenv" / "scripts" / "run-armhf-gates.sh").read_text(encoding="utf-8")
    static_gates = (ROOT / "testenv" / "scripts" / "run-static-gates.sh").read_text(encoding="utf-8")

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
        "upgrade_scheduler",
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
    require("BackendSchedulerService" in bridge, "generated scheduler trait is not imported in bridge")
    require("kap_bridge::upgrade_scheduler(&core.backend)" in port,
            "collection open must delegate V1 scheduler migration to official Anki")
    require("official scheduler upgrade failed" in port,
            "scheduler-upgrade failure must be surfaced explicitly")

    require("crate::services::kap_bridge" in port, "semantic port bypasses the bridge module")
    require("run_backend_" not in port, "port must not call generated numeric dispatch")
    require("anki_backend_command" not in port, "port must not expose generic numeric backend calls")
    require("core.phase != Phase::Idle || core.current.is_some()" in port,
            "next-question ABI must reject advancing while any reviewer card is active")
    require("current card must be rated or buried before advancing" in port,
            "next-question ABI must expose the active-card state-machine failure")

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

    # A blocked GStreamer/device-route helper must never keep the reviewer open
    # indefinitely during cleanup. The production host must bound SIGTERM,
    # force-kill a wedged helper, reap it, and expose the same path as a host
    # regression self-test that is wired into the canonical static gate.
    require("#define AUDIO_STOP_GRACE_MS" in app,
            "native host has no bounded audio shutdown grace period")
    require("reap_child_until" in app,
            "native host has no bounded audio child reaper")
    require("kill(pid, SIGKILL)" in app,
            "native host cannot force-stop a wedged audio helper")
    require("--self-test-audio-supervision" in app,
            "native host does not expose the audio supervision regression path")
    require(
        'run "$BUILD/kap-app-host" --self-test-audio-supervision' in static_gates,
        "static gates do not execute the audio supervision regression",
    )

    require("--print-sysroot" in armhf_gates,
            "ARMHF gate must derive compatibility from the target sysroot")
    require("GLIBC_CEILING=${GLIBC_CEILING:-2.35}" not in armhf_gates,
            "ARMHF gate must not use the stale host-like GLIBC 2.35 ceiling")
    require('strings "$libc"' in armhf_gates,
            "ARMHF gate must derive the target libc symbol-version ceiling")

    runtime_files = [
        ROOT / "core" / "src" / "port.rs",
        ROOT / "core" / "src" / "services_bridge.rs",
        *app_files,
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
