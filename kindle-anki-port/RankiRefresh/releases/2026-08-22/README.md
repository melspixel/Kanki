# RankiRefresh — release 2026-08-22

This directory preserves the user-supplied RankiRefresh/Kanki release artifact built on 2026-08-22 and the engineering process that can be recovered from the artifact itself.

## Artifact identity

- Package: `Kanki-release-2026-08-22.zip`
- User-provided SHA-256: `a91dfe8b95d55469b567307951c4981aa5492d9ea763926f4557cd6f9dd7d002`
- Size: 35,470,206 bytes
- Embedded build identifier: `93be8aa`
- Embedded build date: `2026-08-22`
- Backend version identified by the binary: Anki `26.08`

## What is stored here

- `dist/` — the exact uploaded ZIP, checksum, unpacked `ranki/` runtime tree, and generated file/ABI manifests.
- `source-base/` — the last fully preserved RankiRefresh source tree from Diagnostic 1. It is included as a complete Git tree, not a patch set.
- `recovered-source/` — source-readable material recovered exactly from this release: launcher/fingerprint scripts from the package and the CSS/JavaScript payload embedded inside `libkanki-webkit-armhf.so`.
- `RELEASE_NOTES.md` — user-visible and engineering changes relative to Diagnostic 1.
- `BUILD_PROCESS.md` — the build/release process reconstructed from the package, source lineage, and binary audit.
- `SOURCE_STATUS.md` — precise statement of what source is exact, what is recovered, and what cannot be claimed from the supplied artifact.
- `PROVENANCE.md` — Drive/GitHub/archive identities.

## Important provenance boundary

`KANKI_BUILD.txt` contains `build=93be8aa`, but that identifier is not resolvable as a commit in `melspixel/Kanki`, and the uploaded ZIP does not contain the original C source tree used for that build. This repository therefore does **not** invent an exact source commit.

The compiled package is authoritative for this release. `source-base/` records the complete known lineage, while `recovered-source/` records the byte-exact source-readable pieces that can be extracted from the release itself. If the exact `93be8aa` source becomes available later, it should be added alongside this record rather than rewriting this provenance.
