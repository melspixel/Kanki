# Reference implementations and attribution policy

Updated: 2026-08-22 UTC

## Purpose

Kindle Anki Port is an independent desktop-Anki-to-Kindle port, but it is not
developed in isolation. Existing Kindle applications provide valuable evidence
about Lab126 window-manager conventions, GTK2/WebKitGTK1 behavior, the system
keyboard, installation layout, touch interaction, audio routing and lifecycle.

The project may reproduce a documented behavior or selectively adapt code when
the source license is compatible. It does not make another project a runtime or
build dependency, and it does not import an alternative scheduler, renderer or
sync implementation in place of official Anki.

## Rules

1. Pin every consulted implementation to a repository commit or release.
2. Separate observed behavior from copied source.
3. Treat a repository with no established license as **reference-only**: study
   interfaces and behavior, then write an independent implementation.
4. When code is adapted from a compatible licensed source, retain the required
   copyright/license notice in the affected file and record the exact origin
   below.
5. Never import user data, credentials, firmware, proprietary rootfs files or
   device identifiers from a reference project.
6. Never add deck-name, note-type or field-specific production branches.
7. Official Anki remains authoritative for collection, scheduler, FSRS,
   rendering, typed-answer comparison, cloze, AV, media, sync and undo.

## Authoritative semantic dependency

### Anki

- Repository: `ankitects/anki`
- Commit: `e5a6fbe27fdd4d57d5f712191b4a753032e57853`
- Release: Anki 26.08.1
- Role: authoritative Rust backend and semantic implementation.
- Integration: deterministic maintained overlay plus named `kap_*` C ABI.

## Kindle behavior references

### Ranki

- Repository: `crazy-electron/ranki`
- Audited commit: `d671ee657f0c411474d2afff3bf9cbb49be2fb44`
- Role: principal Kindle platform-behavior reference.
- Relevant proven patterns:
  - Vala/GTK2/WebKitGTK application structure;
  - Lab126 window-title/application identity convention;
  - `com.lab126.keyboard` open/close behavior;
  - KUAL installation layout and `/mnt/us/anki_data` placement;
  - basic deck tree, review, bury, sync and media behavior using real Anki.
- Boundary: Ranki is not a production, build or packaging dependency. Its
  numeric protobuf service/method dispatch, page-reloading reviewer and other
  runtime code are not imported.
- License handling: no repository license file was found during this audit, so
  Ranki source is reference-only unless its license is later established.

### KindlePuzzles / Gargoyle Kindle support

- Repository: `kbarni/kindlepuzzles`
- Audited commit: `9f67dd04634d16dfa2e8eeef13eb582b8225e49e`
- Relevant files:
  - `gtk-launcher/launcher.c` for the Awesome/Lab126 window-title convention;
  - `gtk_utils.c` for OpenLIPC keyboard visibility/open behavior.
- License observed in `gtk_utils.c`: GNU GPL version 2 or later.
- Current use: behavior reference only; Kindle Anki Port uses an independently
  written direct `lipc-set-prop` adapter instead of linking OpenLIPC or copying
  the Gargoyle implementation.

### em-dash

- Repository: `emlyn-m/em-dash`
- Audited commit: `f8c260636dc4fa811c7e470b8b4626985a188172`
- Relevant file: `src/widgets/keyboard.cpp`.
- Relevant pattern: invoke `/usr/bin/lipc-set-prop` without a shell and wait for
  the child process when opening or closing `com.lab126.keyboard`.
- License handling: a repository license file was not established during this
  audit, so the source is reference-only. The Kanki adapter is independently
  written.

### Kindle Explorer

- Repository: `anakod/kindle-explorer`
- Audited commit: `134d04e20d4eaa83a51369eaa80fd3fa007a4d46`
- Relevant file: `trunk/FileData.h`.
- Relevant pattern: Lab126 keyboard open values use
  `<application-id>:<layout>:<mode>` and close values use the application ID.
- License handling: reference-only unless a compatible repository license is
  established.

## Build and ABI references

### KindleHF koxtoolchain

- Project: KOReader koxtoolchain
- Release: `2025.05`
- Target triple: `arm-kindlehf-linux-gnueabihf`
- Role: pinned ARM hard-float compiler/sysroot input; not an application runtime
  dependency.

### Exact PW6 firmware runtime

- Firmware: Paperwhite 12th generation / PW6, 5.19.6 (4832160042)
- Role: private checksum-verified target runtime oracle for QEMU and ABI checks.
- Firmware, rootfs image and proprietary libraries are never committed.

## Current clean-room adaptation record

The 2026-08-22 platform-reference checkpoint adds:

- a Lab126/Awesome-compatible application window identity;
- a native `ime/open` and `ime/close` bridge for typed-answer focus;
- direct argument-vector execution of `lipc-set-prop`, without `/bin/sh`;
- bounded child waiting and lifecycle cleanup;
- reviewer fixtures that verify IME open/close ordering around answer reveal.

The implementation was written for the existing C/JavaScript Kanki architecture
from the observed interfaces above. No Ranki, em-dash or Kindle Explorer source
was copied verbatim in this checkpoint.
