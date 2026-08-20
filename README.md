# Kanki

Kindle-oriented compatibility layer for [crazy-electron/ranki](https://github.com/crazy-electron/ranki).

Goals:

- keep Ranki's real Anki backend and existing scheduling/sync behavior;
- stop non-fatal GTK/GLib/WebKit diagnostics from being painted over the e-ink UI;
- provide an `Audio` compatibility shim for Kindle's old WebKitGTK;
- route Anki media playback through Kindle's native `mixersink` audio path, so connected Bluetooth headphones can be used.

## Architecture

The upstream Ranki ARM binaries are left unchanged. Kanki adds two small components:

1. `libkanki-webkit-<arch>.so`: an `LD_PRELOAD` shim that injects a minimal `window.Audio` implementation into HTML loaded by Ranki's WebKit view. `Audio.play()` sends a localhost request to the native helper.
2. `kanki-audio-<arch>`: a loopback-only HTTP helper that validates media paths, decodes local Anki audio with miniaudio, and streams 16-bit stereo PCM to Kindle's GStreamer `mixersink`.

The launcher also redirects Ranki's stdout/stderr to `ranki.log` instead of the display layer.

## Audio

The first build supports local MP3, FLAC, and WAV files exposed through card JavaScript's `Audio` API. The helper resamples to 44.1 kHz, signed 16-bit stereo PCM before handing audio to the Kindle mixer. OGG/Vorbis, AAC, Anki TTS, and sophisticated browser audio event semantics are not implemented yet.

Only one pronunciation is allowed to play at a time. Starting another sound or calling `pause()` terminates the complete decoder/GStreamer process group so stale audio cannot continue in the background.

## Installation

1. Back up `/mnt/us/anki_data` if desired. Kanki does not intentionally modify or replace that directory.
2. Remove any old `/mnt/us/extensions/ranki/` directory and `/mnt/us/documents/shortcut_ranki.sh` shortcut.
3. Extract the built `kanki.zip` so that its `ranki/` directory becomes `/mnt/us/extensions/ranki/`.
4. Optionally copy `/mnt/us/extensions/ranki/shortcut_ranki.sh` to `/mnt/us/documents/` for a library shortcut. KUAL can also launch the extension directly.
5. Connect Bluetooth headphones in the stock Kindle UI before launching Ranki.

If something fails, inspect `/mnt/us/extensions/ranki/ranki.log`. Non-fatal GTK/GLib/WebKit diagnostics should stay in that log instead of being painted over the review screen.

## Safety

The audio server listens only on `127.0.0.1`, only reads files under the configured `collection.media` directory, rejects parent-directory traversal, and is terminated when Ranki exits. Release packages are assembled from a fresh upstream Ranki release, so a local AnkiWeb token is never baked into the build artifact.

## Build

GitHub Actions cross-compiles static ARMHF and ARMEL audio helpers, builds libc-version-independent WebKit preload shims, downloads the latest upstream `ranki.zip`, replaces the launcher, and emits a ready-to-test package plus SHA-256 checksum.

## Status

Experimental first hardware-test build. The primary targets are the observed `ReferenceError: Can't find variable: Audio` failure and GTK/GLib/WebKit diagnostic text leaking onto the Kindle display.
