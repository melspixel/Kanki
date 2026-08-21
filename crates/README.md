# Rust workspace components

The five crates in this directory are one Kanki workspace. They are **not** five independent projects. Cleanup should distinguish production/runtime code from host-side models and stale scaffolding before removing anything.

## Current classification

- `kanki-domain` — **host model/test oracle**. Shared deterministic review/deck types; used by other Rust crates.
- `kanki-renderer` — **host model/test oracle**. Reviewer packet/document policy; used by `kanki-app` self-tests.
- `kanki-platform` — **host capability/test oracle**. Models the Lab126 CSS-pixel feature path in pure/testable Rust while the actual package currently implements that path in `device/kanki_device.c`.
- `kanki-app` — **host self-test entry point**. Depends on `kanki-domain` and `kanki-renderer`; not the Kindle GTK executable.
- `kanki-backend` — **candidate obsolete scaffold / stale host adapter; verify locally before removal**. No current workspace crate depends on it, while its JSON/ABI model reflects an older bridge shape. For example, its `BuildInfo` expects `api_version/anki_version/architecture/typed_backend`, whereas the current production bridge exposes `bridge_api/anki_release/anki_commit/schema_max`; its review DTO also predates the current autoplay/replay fields and prepared-answer path. It should not be treated as the production backend implementation.

The real Kindle package currently uses:

- pinned Anki source + `bridge/anki_bridge.rs` / `bridge/sync_bridge.rs` for backend semantics;
- native C under `device/` for the actual Kindle application/platform processes.

Therefore “not shipped in the ZIP” does not automatically mean “useless”: domain/renderer/platform Rust code can still be valuable as host-side oracles. But a stale, unreferenced adapter is actively confusing and should be removed once a local baseline proves nothing depends on it.

## Removal rule

Before deleting or merging a crate, establish one of these categories with evidence:

1. production dependency;
2. host model/test oracle;
3. planned dependency with an active milestone;
4. obsolete scaffold.

Only category 4 should be removed.

For `kanki-backend`, the next local-maintainer step is:

1. run `sh tools/run_host_gates.sh` on `repo-cleanup-v1`;
2. confirm no package/build/test path imports the crate;
3. remove it from the workspace and delete the crate in a dedicated commit;
4. rerun host gates;
5. update root/documentation references in the same cleanup PR.

Record final classification changes in `docs/REPOSITORY_CLEANUP.md` or an ADR when architecture is affected.
