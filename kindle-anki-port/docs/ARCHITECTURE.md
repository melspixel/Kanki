# Architecture

## Definition

This is a platform port of the desktop Anki reviewer, not a renderer patch set.
The official Anki source remains authoritative for collection, scheduling,
rendering, typed-answer comparison, media and sync. Kindle code replaces Qt,
Chromium, desktop audio and operating-system lifecycle primitives.

## Layers

### Official Anki core

The pinned `anki` Rust crate owns schema migrations, transactions, scheduling,
queue construction, template rendering, AV extraction, answer comparison,
cloze extraction, media metadata, sync and undo. The port does not reproduce
those algorithms.

### Reviewer service

`core/src/port.rs` ports the state machine coordinated by `aqt/reviewer.py`:

`Idle -> Question -> Answer -> Transition -> Question/Finished`

It owns queue snapshots, AV queues, elapsed time, typed-answer preparation,
rating validation, scheduling states, bury and end-of-review behavior. The web
page cannot mutate scheduling directly.

### Renderer contract

A single persistent WebView retains one `#qa` node. Question and answer content
replace its children without reloading the shell. Note-type CSS is preserved.
The platform stylesheet owns only chrome, semantic replay controls, typed input
accessibility, error surfaces and page navigation.

The compatibility layer translates unsupported browser features generically.
It never recognizes a deck, field, logo or card product.

### Kindle platform adapter

A small C process dynamically binds Kindle-provided GTK 2, WebKitGTK 1 and
GObject ABIs. It owns window/focus/fullscreen, native/web transport, CSS pixel
configuration, touch paging, virtual keyboard focus, audio supervision,
single-instance activation and clean shutdown. It contains no Anki semantics.

### Supervisor/package

The launcher verifies the manifest, validates PID ownership through `/proc`,
raises an existing instance, backs up the collection before first open, and
cleans demonstrably stale state. The application lives at
`/mnt/us/extensions/kindle-anki-port`; user data remains in
`/mnt/us/anki_data`.

## Protocols

Rust/native uses named C symbols and UTF-8 JSON envelopes. Web/native uses a
versioned allow-listed `kap://v1/<operation>` protocol with request IDs and
bounded inputs. No protobuf service or method indices are exposed.

## Failure containment

- Collection operations are serialized by the reviewer service.
- Audio is a separate process and can be restarted after Bluetooth changes.
- A renderer exception fails the current render, not the process.
- A PID is signalled only after executable/path verification.
- Shutdown is idempotent: stop audio, persist session, close collection,
  remove IPC/PID state, destroy UI, exit.
