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
2. `kanki-audio-<arch>`: a loopback-only HTTP helper that validates media paths, decodes common Anki audio formats with miniaudio, and streams 16-bit stereo PCM to Kindle's GStreamer `mixersink`.

The launcher also redirects Ranki's stdout/stderr to `ranki.log` instead of the display layer.

## Safety

The audio server listens only on `127.0.0.1`, only reads files under the configured `collection.media` directory, rejects parent-directory traversal, and is terminated when Ranki exits.

## Status

Experimental. The first target is the currently observed failure `ReferenceError: Can't find variable: Audio` on Kindle WebKitGTK.
