# Rust workspace components

The crates here are host-side components of one Kanki workspace, not five
independent products. The canonical Kindle package currently builds the pinned
Anki backend with `bridge/` and the source-owned C executables under `device/`;
none of these workspace crates is copied into the ZIP.

## Audited classification

- `kanki-domain` — **host-test-oracle**. It exercises deterministic
  question/answer/rating state and shared fixture types.
- `kanki-renderer` — **host-test-oracle**. It embeds the real reviewer assets
  and checks packet/body-class, persistent-`#qa`, deck-agnostic and SVG policy.
- `kanki-platform` — **host-test-oracle**. It models the Lab126 capability and
  density decision; production symbol loading/configuration is in
  `device/kanki_device.c` and the fixed rootfs audit.
- `kanki-app` — **host-test-oracle**. `tools/run_host_gates.sh` runs its
  deterministic self-test; it is not the Kindle GTK executable.
- `kanki-backend` — **obsolete-scaffold**. No package, tool, test harness or
  other workspace crate depends on it. It is an unused Rust loader for an
  earlier review ABI surface: it lacks the production
  `kanki_prepare_answer_json` flow, current typed-answer/playback packet fields
  and the sync API. No active milestone plans to replace the native C client
  with it. Remove it only in a dedicated commit with before/after host gates.

There is currently no crate in the **production** or **planned** category.
That statement is about the five workspace crates, not about Kanki's Rust
production backend: pinned Anki plus `bridge/anki_bridge.rs` and
`bridge/sync_bridge.rs` remain production Rust code.

Before deleting or merging a crate, establish one of these classifications with evidence:

1. production dependency;
2. host model/test oracle;
3. planned dependency with an active milestone;
4. obsolete scaffold.

Only category 4 should be removed. Record a future role change in this file;
use an ADR if it changes architecture rather than merely documenting current
build ownership.
