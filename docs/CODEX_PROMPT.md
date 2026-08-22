# Suggested prompt for local Codex

Copy the block below into a local Codex session started from the repository root.

```text
You are taking over the Kanki rewrite in this repository. Work as the primary maintainer, not as a one-off patch author.

Before editing anything, read in this order:
1. AGENTS.md
2. docs/CODEX_HANDOFF.md
3. docs/STATUS.md
4. docs/ARCHITECTURE.md
5. docs/ANKI_DESKTOP_PARITY.md
6. docs/TESTING.md
7. docs/LOCAL_BUILD.md
8. docs/HANDOFF.md
9. docs/adr/*
Then inspect PR #10 / issue #11 if GitHub access is available.

Primary branch: rewrite-v1.
main is the last accepted legacy line and must not be rewritten during takeover.

Your goal is to finish a source-owned Kindle Anki client for PW6, using pinned Anki 26.08.1 and Kindle-native GTK2/WebKit/Lab126 behavior, with no RAnki runtime patching and no deck-specific CSS hacks.

Important invariants:
- RAnki is reference-only; never ship or patch it.
- No LD_PRELOAD backend redirection.
- No hard-coded 420px viewport, broad media-query rewriting, global font scaling, or deck-specific selectors.
- Scheduling/rendering/sync/collection semantics come from the pinned Anki backend.
- Anki access remains semantic/typed; do not reintroduce numeric protobuf service/method dispatch.
- Reviewer is one persistent WebView with one persistent #qa.
- Do not globally resize arbitrary SVG/images to fix audio controls.
- Never delete/replace /mnt/us/anki_data.
- New client installs under /mnt/us/extensions/kanki, separate from legacy /mnt/us/extensions/ranki.
- Builds are self-identifying and manifest-verified.
- Default diagnostics are bounded/privacy-safe; raw note/card HTML is explicit opt-in only.

GitHub-hosted Actions are currently unreliable before the first workflow step. Do not wait for Actions and do not treat zero-step red jobs as code failures.

First session procedure:
1. Record baseline:
   git checkout rewrite-v1
   git pull --ff-only
   git status --short
   git rev-parse HEAD
   git submodule status
   git branch -a
2. Initialize pinned submodules if needed.
3. Read the repository tree and classify every top-level component as production, test, build, docs, third-party reference, or historical/transition artifact.
4. Run host baseline:
   sh tools/run_host_gates.sh
5. Run the canonical local Kindle package build:
   bash tools/local_package_docker.sh
6. Capture the first real compiler/test/package failure and fix one failure class at a time.
7. Do not do a mass directory rename before obtaining a real local baseline.

Repository cleanup is also part of the task. The repo currently has historical experimental branches, overlapping docs/workflows, and transition scripts. Clean it carefully:
- preserve branch tips first (record branch->SHA or archival tags), then delete obsolete experimental branches after proving rewrite-v1 contains everything needed;
- audit tools/patch_sync_ui.py and tools/patch_type_answer_ui.py; remove them if their changes are already canonical, otherwise convert/document them as deterministic build steps;
- audit the five Rust crates and label each as production, test oracle, planned, or obsolete scaffold; remove only proven obsolete scaffolding;
- reduce duplicated build logic: tools/build_kindle_package.sh is canonical; CI YAML should orchestrate it, not duplicate it;
- consolidate CI only after local baselines are healthy;
- use docs/README.md ownership rules to deduplicate documentation without losing information;
- prefer small git mv/refactor commits, not a single “cleanup everything” commit.

Technical verification priorities:
- typed Anki host build and disposable collection tests;
- queue/render/AV/type-answer/answer/bury parity;
- effective deck-config autoplay and answer-side question-audio replay;
- sync/full-sync/media-sync lifecycle;
- ARMHF Anki backend and ABI/GLIBC audit;
- native GTK2/WebKit app, Lab126 CSS pixels and persistent reviewer lifecycle;
- generic old-WebKit CSS compatibility without per-deck changes;
- scripts/images/SVG/audio/MathJax/cloze/cardN/long-card behavior;
- original representative APKG decks (including COCA) without modifying them;
- diagnostics creation, bounds and privacy;
- reproducible package, clean install, rollback, and PW6 hardware acceptance.

When a card differs from desktop Anki, diagnose in this order:
Anki backend render -> Kanki packet -> persistent reviewer DOM -> generic CSS compatibility -> Kindle computed style/geometry -> Lab126 CSS pixel/zoom -> fonts/media.
Do not jump to deck-specific CSS.

At the end of every substantial work session, commit code and update:
- docs/STATUS.md with exact SHA, what passed, first failure, and next command;
- docs/CODEX_HANDOFF.md if takeover instructions or repository layout changed;
- docs/HANDOFF.md for operational/release changes;
- issue #11 with evidence if available;
- an ADR for architecture changes.

Do not claim completion or produce a release until one exact candidate SHA has current evidence for host tests, typed Anki integration, ARMHF/ABI, renderer/CSS/audio/diagnostics, reproducible package, and PW6 hardware acceptance.

Start now by auditing the current tree/branches and running the host/local build baseline. Report the first concrete failure and your proposed minimal fix before broad refactoring.
```
