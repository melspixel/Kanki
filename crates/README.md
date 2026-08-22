# Rust workspace components

The four remaining crates are host-side components of one Kanki workspace,
not independent products. The canonical Kindle package builds the pinned
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
There is currently no crate in the **production**, **planned** or
**obsolete-scaffold** category. That statement is about the workspace crates,
not about Kanki's Rust
production backend: pinned Anki plus `bridge/anki_bridge.rs` and
`bridge/sync_bridge.rs` remain production Rust code.

## Removed obsolete scaffold

`kanki-backend` was classified **obsolete-scaffold** and removed in a dedicated
cleanup commit. Its only reverse dependency was itself; no package, canonical
tool, integration harness or other workspace crate imported it. The unused
Rust loader lacked the production `kanki_prepare_answer_json` path, current
typed-answer/playback packet fields and the entire sync ABI, and there was no
active milestone to replace the native C client with it. Full host gates are
the required before/after proof for this removal.

Before deleting or merging a crate, establish one of these classifications with evidence:

1. production dependency;
2. host model/test oracle;
3. planned dependency with an active milestone;
4. obsolete scaffold.

Only category 4 should be removed. Record a future role change in this file;
use an ADR if it changes architecture rather than merely documenting current
build ownership.
