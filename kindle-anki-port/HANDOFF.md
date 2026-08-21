# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-21

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Current handoff lineage starts at: `4cf92bcc372f6cd9fcdb6ba72d15a7d7193203ff`
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1)
- Detailed status: `kindle-anki-port/PROGRESS.md`

This file is the authoritative continuation point. Update it after every material build, test, packaging, or release change.

## User-required deliverables

1. Full maintainable source tree committed to GitHub, not only archive chunks.
2. Reproducible build scripts that run in a local/VM environment and can also run in GitHub Actions when quota is available.
3. PW6 ARM hard-float installation archive.
4. SHA-256 checksum, package contents, build provenance, and test report.
5. Final package persisted on GitHub, not only in a temporary chat filesystem.
6. No bundled collection, media, credentials, logs, PID files, or user configuration.
7. No dependency on RAnki, `rewrite-v1`, `LD_PRELOAD`, or prior card-template patch sets.

## Architecture decision

This is a platform port of desktop Anki, not a card-template patch project.

- The pinned official Anki Rust backend remains authoritative for collection, scheduling, rendering, typed-answer comparison, media, sync, and undo.
- A named semantic C ABI exposes only reviewer operations to the Kindle host.
- A native GTK2/WebKitGTK1 process owns the Kindle window, persistent WebView, focus, paging, keyboard, lifecycle, and process supervision.
- An ES5 reviewer shell owns DOM replacement, replay controls, typed-input presentation, and generic old-WebKit compatibility.
- Audio and sync are separate supervised components.

## Current repository state

The branch currently contains a source archive split into `part-00` through `part-08`, `restore.sh`, and `Kindle-Anki-Port-source.zip.sha256`. The verified archive SHA-256 is:

```text
ac234bb5ca8bdb59fef39dd533880dad708b40c2ba03799c5d147e745f997ffa
```

The archive restores a `kindle-anki-port/` project containing:

- semantic Rust/C ABI adapter over the pinned official Anki backend;
- Kindle GTK/WebKit frontend;
- deck and persistent reviewer web runtime;
- lifecycle and synchronization scripts;
- packaging metadata and architecture/release documentation.

The source directory has not yet been materialized into ordinary GitHub files on this branch. Archive chunks are temporary and must be removed after source-tree materialization.

## Latest verified build diagnostic

The latest useful compile diagnostic came from temporary build-farm run `32474571560`, artifact `9443901779`, head `d57c53af1fc263b1681680ffdd2f095fe949109b`.

Earlier infrastructure failures were resolved:

- Anki Fluent translation submodules were initialized;
- compressed overlay sources were decoded correctly;
- the build reached the injected `kap_port.rs` module in the pinned Anki crate.

The current blocking failure is semantic-adapter placement/API visibility:

- 26 Rust errors remain;
- generated backend service methods such as `get_queued_cards`, `answer_card`, `render_existing_card`, `compare_answer`, `extract_cloze_for_typing`, `deck_tree`, and `bury_or_suspend_cards` are private from the injected crate-root module;
- the accompanying type-inference errors are secondary to those inaccessible calls.

The preferred repair is to place a narrow bridge inside Anki's `backend` module, or route through backend-owned `pub(crate)`/collection-level APIs, rather than making generated service methods globally public or calling unstable numeric protobuf indices.

## Actual implementation completeness

Implemented as source but not yet release-validated:

- collection open/close ABI;
- deck tree/current deck/collapse ABI;
- queue, question, reveal, answer, and bury state machine;
- typed-answer marker parsing and reviewer input UI;
- semantic AV marker replacement and replay controls;
- persistent `#qa` reviewer shell;
- generic CSS compatibility and nested-scroll flattening;
- GTK/WebKit host, touch paging, single-instance/lifecycle scaffolding;
- audio worker and launcher/backup scaffolding.

Still missing or not yet adequate:

- no successful host build against the pinned Anki source;
- no ARMHF backend/frontend build;
- `kap-sync` implementation is absent even though the shell script refers to it;
- the archived audio source still uses miniaudio, while Kindle-native GStreamer/mixersink integration must be selected and validated;
- the documentation describes a parity suite, but the archived source currently has only two small Rust parser tests and no complete `tests/` tree;
- no package, ABI/GLIBC report, release asset, or PW6 hardware acceptance exists.

## Execution environment

GitHub Actions runtime quota is exhausted. Iterative compilation and tests must therefore run in the available VM/container environment. GitHub remains the canonical source, progress, handoff, and final-artifact store. Use Actions only for a final independent reproduction when quota is available; lack of Actions minutes must not block local build/test progress.

If work must move to a user's local machine, create/update a repository communication document with exact commands, expected outputs, artifact paths, and unresolved questions so Codex can act as the local executor without relying on chat history.

## Ordered next actions

1. Materialize the verified source archive into ordinary `kindle-anki-port/` files in GitHub and remove archive chunks after verification.
2. Consolidate all later temporary overlays into the canonical source tree.
3. Refactor the Rust adapter into a backend-owned visibility boundary and make host `cargo check`, unit tests, and release build green.
4. Add real integration fixtures for collection open, deck tree, queue, render, typed answer, answer, bury, and close.
5. Implement the official normal/full/media sync adapter and `kap-sync` binary.
6. Replace or validate the audio backend against the Kindle audio stack, including Bluetooth rerouting.
7. Run KindleHF ARM hard-float cross-build for `libanki-kindle.so`, `kap-app`, `kap-audio`, and `kap-sync`.
8. Audit ELF class, interpreter, ABI, exported `kap_*` symbols, dynamic dependencies, and GLIBC ceiling.
9. Add reviewer, lifecycle, package-policy, and repeat-launch tests.
10. Assemble, unpack, inspect, checksum, and persist `Kindle-Anki-Port-PW6-armhf.zip` plus reports on GitHub.
11. Run the PW6 hardware matrix: rendering, typed keyboard, audio/Bluetooth, long-card paging, suspend/resume, and 50 exit/re-enter cycles.

## Release record

Not yet released.

When complete, replace this section with:

- release/tag;
- source commit;
- build environment and command;
- workflow run ID if available;
- artifact/release asset name;
- exact SHA-256;
- automated test results;
- hardware acceptance status and any remaining device-only checks.

## Integrity rule

Do not mark the project complete merely because a ZIP exists locally. Completion requires maintainable GitHub source, a reproducible green build, package audit, GitHub persistence, and this handoff document updated with exact evidence.
