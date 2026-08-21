# Anki integration bridge

This directory defines the semantic boundary between Kanki and the pinned Anki Rust backend.

## Production role

- `anki_bridge.rs` — review/deck/render semantic C ABI compiled into pinned Anki.
- `sync_bridge.rs` — sync/media-sync semantic C ABI compiled into pinned Anki.
- `kanki_bridge.h` / `kanki_sync_bridge.h` — native C headers consumed by Kindle executables.
- `smoke.c` — host ABI/integration smoke harness.

## Invariants

- Application code must use semantic functions, not numeric protobuf service/method IDs.
- The bridge is compiled against the exact pinned Anki source in `third_party/anki`.
- Anki scheduling/rendering/sync logic is not reimplemented here; this layer translates stable Kanki-facing calls into typed Anki service calls.
- ABI changes require matching header, smoke-test, package export and handoff updates.

This is production integration code, not a generated scratch area.
