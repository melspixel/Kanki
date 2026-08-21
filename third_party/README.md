# Pinned upstream references and dependencies

Entries here are gitlinks with explicit commit pins. They are not independent Kanki projects.

- `anki` — production Anki 26.08.1 source used to build the semantic backend bridge.
- `kindle-sdk` — Kindle system/toolchain/reference source.
- `audiobook-koplugin` — pinned Kindle-native GStreamer reference/helper source.
- `ranki-reference` — historical RAnki behavior reference only; never a runtime dependency or package input.

Dependency updates must be explicit, reviewed and reflected in build identity/handoff documentation. Do not replace these pins with floating `latest` behavior.
