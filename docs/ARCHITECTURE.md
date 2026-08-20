# Architecture

## Goal

Kanki is an Anki-compatible reviewer designed against the exact Kindle system it runs on. The target is not visual similarity produced by deck-specific CSS. The target is equivalent reviewer semantics with explicit, minimal substitutions for Kindle I/O.

## Layers

### 1. Anki core

Production uses the pinned `third_party/anki` Rust backend directly. The UI never calls numeric service/method IDs and never owns protobuf wire compatibility. A typed adapter converts Anki messages into the stable types in `kanki-domain`.

Owned by Anki: collection schema, FSRS/scheduler, rendering, sync, media metadata, deck collapse state and AV extraction.

### 2. Domain controller

`kanki-domain` is a small deterministic state machine. It knows question/answer/rating sequencing but no GTK, WebKit, protobuf or Kindle ABI. This makes review behavior testable on a normal host.

### 3. Persistent reviewer

Desktop Anki maintains one reviewer document and replaces `#qa`. Kanki follows the same model. The note type supplies HTML/CSS; Kanki supplies only the reviewer shell, body classes, AV bridge and script lifecycle.

The old design—constructing a new complete HTML page for each side—is prohibited.

### 4. Kindle platform

The platform layer owns:

- GTK2 input/chrome;
- WebKitGTK 1.x integration;
- Lab126 W3C-CSS-pixel and full-content-zoom extensions;
- e-ink refresh policy;
- native audio through GStreamer `mixersink`;
- safe filesystem paths and single-instance lifecycle.

The platform layer is loaded against the audited firmware ABI. It must feature-detect private Lab126 symbols and log the selected path.

## Data flow

```text
Anki Backend -> typed adapter -> ReviewCard -> ReviewSession
                                           -> reviewer JSON packet
persistent WebKit #qa <- evaluate_script <--- renderer
Kindle button/touch -> controller -> typed adapter -> Anki Backend
```

## Failure boundaries

- Collection writes occur only in the typed Anki adapter.
- A rendering error cannot mutate scheduling state.
- A rating is committed only after the answer side is visible.
- Sync and media sync are explicit operations with progress/abort surfaces.
- Device packages contain build IDs and reject mixed component versions.

## What is intentionally not reused

The historical RAnki executable, Vala protobuf bindings, hard-coded service indices, preload redirects, 600px scaling formula and per-load HTML construction are reference material only. They are not runtime dependencies.
