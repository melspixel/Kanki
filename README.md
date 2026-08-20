# Kanki

Kindle-oriented compatibility layer for [crazy-electron/ranki](https://github.com/crazy-electron/ranki).

Kanki keeps Ranki's real Anki backend and scheduling/sync behavior, but replaces the fragile Kindle-specific browser assumptions around it. The goal is that an ordinary Anki deck should render acceptably on Kindle without adding a deck-specific `.kindle` stylesheet.

## Architecture

The upstream Ranki ARM binaries are left unchanged. Kanki adds three compatibility layers:

1. `libkanki-webkit-<arch>.so`: an `LD_PRELOAD` WebKit/GTK shim. It injects a small reviewer shell and ES5 compatibility runtime, caps Ranki's excessive WebView zoom, and suppresses Ranki's unconditional deck-tree `expand_all()` call.
2. `kanki-audio-<arch>`: a loopback-only helper that receives audio requests, resolves local or supported remote media, decodes it with miniaudio, and invokes the Kindle-native GStreamer player.
3. `kanki-gst-play-armhf`: a Kindle-native GStreamer/mixersink bridge that routes PCM through Amazon's audio stack to Bluetooth headphones.

The launcher redirects Ranki's stdout/stderr to `ranki.log` instead of letting GTK/GLib/WebKit diagnostics leak onto the e-ink display.

## Reviewer compatibility

The generic reviewer layer is modeled on current desktop Anki rather than on any particular vocabulary deck. In particular it:

- preserves the deck's own font families, relative font sizes, colors, margins, and semantic hierarchy;
- mirrors Anki's minimal reviewer defaults for body margins, image bounds, lists, preformatted text, and 40 px replay controls;
- exposes `mobile`, `linux`, and `kindle` platform classes on the document root, so existing mobile-specific deck CSS can be reused;
- applies the `card`, `isLin`, and `kindle` classes to the body and removes Ranki's extra `.card.kindle` wrapper to make the DOM closer to Anki's reviewer structure;
- resolves common CSS custom properties (`var(--x)`) before Kindle's old WebKit parses the card, including simple `calc()` expressions used for sizes and spacing;
- avoids very-wide desktop-only `min-width` media rules on Kindle;
- provides a small flex-gap fallback for old WebKit;
- converts raw `[sound:file]` references into Anki-style replay buttons and provides a `window.Audio` fallback for templates that call `new Audio(...).play()`.

This is a compatibility layer, not a full Chromium replacement. Modern JavaScript-heavy templates can still contain features too new for Kindle's WebKit, but their core HTML/CSS should degrade much more cleanly.

## Deck tree

Upstream Ranki currently calls `view.expand_all()` every time the deck list is populated. Kanki suppresses that blanket expansion, so nested decks start collapsed and can be expanded manually. This keeps large hierarchical collections usable on a 7-inch e-ink screen.

## Audio

Local MP3/FLAC/WAV media is supported. Remote pronunciation URLs can be fetched when the Kindle firmware provides `curl`, `wget`, or BusyBox `wget`. Audio is decoded to a standard PCM WAV and handed to the native GStreamer/mixersink bridge. Only one pronunciation is allowed to play at a time.

## Installation

1. Back up `/mnt/us/anki_data` if desired. Kanki does not intentionally replace that directory.
2. Remove the old `/mnt/us/extensions/ranki/` directory and `/mnt/us/documents/shortcut_ranki.sh` shortcut.
3. Extract the built `kanki.zip` so that its `ranki/` directory becomes `/mnt/us/extensions/ranki/`.
4. Optionally copy `/mnt/us/extensions/ranki/shortcut_ranki.sh` to `/mnt/us/documents/` for a library shortcut. KUAL can also launch the extension directly.
5. Connect Bluetooth headphones in the stock Kindle UI before launching Ranki.

If something fails, inspect `/mnt/us/extensions/ranki/ranki.log`.

## Safety

The audio server listens only on `127.0.0.1`; local media access remains constrained to the configured collection media directory. Release packages are assembled from a fresh upstream Ranki release, so a local AnkiWeb token is never baked into the build artifact.

## Build

GitHub Actions validates the ES5 compatibility runtime, embeds the reviewer CSS/JS into a libc-independent ARM preload library, cross-compiles the audio helpers, builds the Kindle-native GStreamer bridge with koxtoolchain, downloads the latest upstream `ranki.zip`, and emits a ready-to-test package plus SHA-256 checksum.
