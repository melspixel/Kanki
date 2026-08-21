# Third-party notices

Kanki is AGPL-3.0-or-later. The project builds against exact, pinned source revisions or checksum-pinned build-tool releases.

## Anki

- Project: Anki
- Source: https://github.com/ankitects/anki
- Pinned revision: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (26.08.1)
- License: AGPL-3.0-or-later

The production backend is compiled from this source with Kanki's semantic bridge module.

## KOReader koxtoolchain / KindleHF cross toolchain

- Project: koxtoolchain
- Source: https://github.com/koreader/koxtoolchain
- Pinned release: `2026.08`
- Build asset: `kindlehf.tar.zst`
- SHA-256: `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`

The toolchain is a build-time dependency only and is not redistributed inside the Kanki Kindle package. `tools/install_kindlehf_toolchain.sh` verifies the checksum before extraction; workflows must not use a floating `latest` toolchain URL.

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

## MathJax

- Project: MathJax
- Source: https://registry.npmjs.org/mathjax/-/mathjax-2.7.9.tgz
- Pinned release: `2.7.9`
- SHA-256: `7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786`
- License: Apache-2.0

Kanki packages the checksum-verified upstream JavaScript distribution as a source-owned reviewer dependency. The persistent reviewer loads it once with the `TeX-AMS_SVG-full` configuration and scopes subsequent formula typesetting to its persistent `#qa`; ordinary card SVG and images are not rewritten. This runtime is not copied from or loaded through RAnki.

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
