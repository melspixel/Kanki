# ADR 0006: Bind typed Anki TTS to the fixed PW6 runtime

- Status: accepted
- Date: 2026-08-22

## Context

The typed Anki bridge preserves each TTS tag's text, language, preferred voice
list and speed. The reviewer preserved those fields for a direct replay, but
its ordered autoplay request retained only the text. The native audio service
then discarded every field except text.

The package also delegated TTS to the pinned audiobook WAV helper. That helper
builds `ttssrc` with `content-texts`, then falls back to `text`. Executing
`gst-inspect-1.0 ttssrc` against the authenticated PW6 5.19.6 rootfs shows that
neither property exists there. The fixed target exposes writable
`textsource`, `voicelang` and `speed` properties instead. A successful factory
probe therefore did not prove that Kanki's TTS pipeline could be constructed.

## Decision

The reviewer sends text, language, voice preferences and speed for both direct
and ordered TTS requests. A source-owned bounded C protocol parser is shared by
the loopback service and executable host tests. It rejects malformed/non-finite
values and maps requested speed to the PW6 property's documented 0.26–10 range.

Sound files keep the existing source-built path: Kanki resolves media inside
`collection.media`, decodes to PCM/WAV and invokes the pinned WAV helper, which
routes to `mixersink`.

TTS no longer invokes that helper's incompatible `--ttssrc` mode. A Kanki-owned
runtime adapter dynamically loads the fixed firmware GStreamer/GObject ABI,
builds a constant `ttssrc` to `mixersink stream-type=Music sync=true` pipeline,
and sets note text through `textsource`, language through `voicelang` and speed
through `speed`. User text is passed through `g_object_set`; it is never
interpolated into a shell command or pipeline description.

PW6 exposes no voice-ID property. Kanki preserves Anki's ordered voice list at
the semantic protocol boundary but cannot claim voice-name selection; the
device chooses its installed voice for `voicelang`. This limitation remains
explicit until a fixed-firmware API or hardware evidence supports a stronger
mapping.

Host tests execute the browser request, native parser and the production TTS
adapter against fake GStreamer/GObject ABIs. The fixed-rootfs audit executes
`gst-inspect-1.0`, requires the three writable properties, and runs the
packaged ARMHF pipeline probe through the PW6 loader.

## Boundaries

The authenticated TTS squashfs is mounted only inside the read-only rootfs
audit model and is never packaged. This decision does not patch firmware,
RAnki or the audiobook submodule. It does not alter Anki AV extraction,
autoplay decisions or ordering semantics.

The host and QEMU probes establish protocol, loader, property and pipeline
compatibility. They do not execute Lab126 audio services or prove audible
output, AirPods routing, language availability, interruption behavior or
repeated replay on a physical PW6. Those remain hardware acceptance work.

## Rejected alternatives

- Keep using `content-texts`/`text`: both are absent from the fixed PW6 plugin.
- Patch the pinned audiobook submodule during packaging: that recreates a
  patch-driven build and leaves semantic ownership outside Kanki.
- Invoke `gst-launch` with card text in a command/pipeline string: quoting and
  parser interpretation would make arbitrary note text unsafe.
- Drop language, voices and speed from ordered playback: that silently changes
  the typed semantics supplied by the pinned Anki backend.
- Package Amazon TTS libraries: those belong to firmware and are neither a
  Kanki dependency artifact nor redistributable package content.
