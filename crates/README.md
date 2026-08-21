# Rust workspace components

The five crates in this directory are one Kanki workspace. During cleanup, classify each crate by actual role before removing or merging it.

Current intended roles:

- `kanki-domain` — deterministic review/deck state and shared data model; host-test oracle / reusable domain layer.
- `kanki-backend` — application-facing backend abstraction; host architecture boundary.
- `kanki-renderer` — reviewer packet/rendering policy model; host-test oracle for renderer semantics.
- `kanki-platform` — platform abstraction boundary.
- `kanki-app` — host/self-test executable and integration entry point.

The Kindle production shell is currently native C and the production Anki bridge is compiled into pinned Anki source, so not every Rust crate necessarily ships in the final Kindle package. That alone does not make a crate obsolete.

Before deleting or merging a crate, establish one of these classifications with evidence:

1. production dependency;
2. host model/test oracle;
3. planned dependency with an active milestone;
4. obsolete scaffold.

Only category 4 should be removed. Record the decision in `docs/REPOSITORY_CLEANUP.md` or an ADR when it changes architecture.
