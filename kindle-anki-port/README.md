# Kindle Anki Port

A source-driven port of the official desktop Anki reviewer to Kindle Linux.

This directory is an independent project. It does not import, link, package, or
execute RAnki, `rewrite-v1`, or any previous Kindle card-template patch set.
The pinned official Ankitects Anki source tree is the behavioral source of
truth; Kindle-specific code replaces only platform primitives.

## Product boundary

The first production target is the complete study loop:

- collection open/migration and recovery;
- deck tree, queue, scheduling, intervals, bury and answering;
- official template rendering, note CSS, media and card scripts;
- semantic sound/TTS packets and replay controls;
- typed answers, including `cloze:` and `nc:` filters;
- persistent reviewer page, touch paging, e-ink-safe controls;
- official collection/media synchronization;
- deterministic shutdown, relaunch and single-instance activation.

Desktop-only authoring windows, add-ons and statistics dashboards are not
reimplemented on-device. They remain desktop responsibilities and are not part
of the reviewer port.

## Layout

- `core/`: semantic C ABI over the pinned official Anki Rust backend.
- `native/`: Kindle GTK/WebKit process and audio worker.
- `web/`: persistent deck/reviewer runtime, ES5-compatible with WebKit 534.
- `scripts/`: lifecycle, backup and synchronization launchers.
- `tests/`: parity, policy, lifecycle and package gates.
- `docs/`: source map, architecture, parity matrix and release evidence.

## Data and installation

Application files: `/mnt/us/extensions/kindle-anki-port`

Collection/media: `/mnt/us/anki_data`

The release archive never contains a collection, credentials, logs, PID files,
or user configuration.
