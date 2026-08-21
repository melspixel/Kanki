# Kanki maintainer instructions

This repository is in a source-owned rewrite. If you are an automated coding agent or a maintainer arriving without chat history, **do not start by editing code**.

Read, in order:

1. `docs/CODEX_HANDOFF.md`
2. `docs/STATUS.md`
3. `docs/ARCHITECTURE.md`
4. `docs/ANKI_DESKTOP_PARITY.md`
5. `docs/TESTING.md`
6. `docs/LOCAL_BUILD.md`
7. issue #11 and PR #10

## Authoritative branches

- `main` = last accepted legacy line. Do not rewrite it during takeover.
- `rewrite-v1` = active source-owned replacement.
- PR #10 = integration PR into `main`, intentionally Draft until closure.
- issue #11 = verification/closure authority. A checkbox means evidence exists, not merely that code was written.

## Non-negotiable invariants

- RAnki is reference-only. Never execute, patch, preload, or ship it in the rewrite.
- No `LD_PRELOAD` backend redirection.
- No hard-coded 420px viewport, media-query rewriting, or global font/zoom compensation.
- Use the pinned Anki backend for scheduling, rendering, collection and sync semantics.
- Application-facing Anki access must remain semantic/typed; do not reintroduce opaque numeric service/method IDs.
- Reviewer lifetime is one persistent WebView with one persistent `#qa` document.
- Card compatibility must be deck-agnostic. Never add COCA-specific, note-type-specific, dictionary-specific, or user-deck-specific CSS/logic.
- Semantic audio controls may be sized; unrelated SVG/images must not be globally resized.
- `/mnt/us/anki_data` is user data. Install, upgrade, rollback, diagnostics and tests must never delete or replace it.
- New rewrite installs under `/mnt/us/extensions/kanki`, separate from legacy `/mnt/us/extensions/ranki`.
- Release artifacts must be self-identifying and manifest-verified; mixed component versions are errors.
- Diagnostics must always provide bounded privacy-safe metrics; raw card HTML/CSS capture is explicit opt-in only.

## Build strategy

GitHub-hosted Actions are currently unreliable at the runner-allocation layer. The canonical package definition is **not** a workflow body; it is:

```sh
bash tools/build_kindle_package.sh
```

For macOS/Apple Silicon, use the supported Linux/amd64 Docker wrapper:

```sh
bash tools/local_package_docker.sh
```

For host gates:

```sh
sh tools/run_host_gates.sh
```

Do not create a second undocumented build recipe. Fix the canonical scripts instead.

## Takeover rule

Before a structural cleanup or feature change:

1. record `git status`, current SHA, submodule SHAs and active branch;
2. run the narrowest available baseline tests;
3. classify files as production, test, build, documentation, third-party reference, or historical transition artifact;
4. preserve behavior while organizing; do not mix repository cleanup with semantic renderer/backend changes in the same commit unless unavoidable;
5. update `docs/STATUS.md`, `docs/CODEX_HANDOFF.md` and issue #11 when verified state or the next blocker changes.

## Definition of done

Do not mark the rewrite complete, merge PR #10, or publish 1.0 until one exact candidate SHA has current evidence for host tests, typed Anki integration, ARMHF/ABI, renderer/CSS/audio/diagnostics, reproducible package, and PW6 hardware acceptance.
