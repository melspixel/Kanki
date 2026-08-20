# Third-party notices

Kanki is AGPL-3.0-or-later. The project builds against exact, pinned source revisions.

## Anki

- Project: Anki
- Source: https://github.com/ankitects/anki
- Pinned revision: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- License: AGPL-3.0-or-later

The production backend is compiled from this source with Kanki's semantic bridge module.

## kindle-gst-play reference implementation

- Project: audiobook.koplugin
- Source: https://github.com/stradichenko/audiobook.koplugin
- Pinned revision: `62edf76feb1b7f4af2f01754957e8d57eb3e7d67`
- File used at build time: `kindle/gst-play.c`
- License declared by that file: AGPL-3.0-only

Kanki compiles the pinned source as a native Kindle GStreamer/mixersink helper.

## miniaudio

- Project: miniaudio
- Source: https://github.com/mackron/miniaudio
- Pinned revision: `4a5b74bef029b3592c54b6048650ee5f972c1a48` (0.11.21)
- License: public domain or MIT No Attribution, at the user's option

The header is fetched from the pinned revision during CI and used only for media decoding in `kanki-audio`.

## RAnki reference

- Project: RAnki
- Source: https://github.com/crazy-electron/ranki
- Pinned revision: `d671ee657f0c411474d2afff3bf9cbb49be2fb44`
- License: GPL-3.0

RAnki is retained only as historical/reference source. No RAnki executable or source object is linked into the rewritten runtime.

## Kindle SDK

- Project: KindleModding Kindle SDK
- Source: https://github.com/KindleModding/kindle-sdk
- Pinned revision: `b4a6c99d718a7cf74935f36105c62491b4336a61`

Amazon firmware, rootfs images and proprietary libraries are not redistributed by Kanki.
