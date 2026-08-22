# RankiRefresh

RankiRefresh is the maintained Kanki/RAnki refresh subproject for Kindle. It preserves both complete source lineage and the exact compiled packages that were actually tested/shipped.

## Current preserved release

Latest artifact-backed release:

- date: `2026-08-22`
- embedded build identifier: `93be8aa`
- package: `releases/2026-08-22/dist/Kanki-release-2026-08-22.zip`
- SHA-256: `a91dfe8b95d55469b567307951c4981aa5492d9ea763926f4557cd6f9dd7d002`

See `releases/2026-08-22/` for release notes, the build/process reconstruction, exact binaries, unpacked runtime, recovered embedded renderer source, and provenance boundaries.

## Project layout

- `source/` — the complete frozen Diagnostic 1 source tree (`f178e5e...`, tree `8fb4d253...`). This remains the last fully preserved exact Git source lineage.
- `dist/` — the fully materialized Diagnostic 1 compiled result, including the install ZIP and unpacked runtime.
- `releases/2026-08-22/` — versioned record of the newer user-built release. It includes a complete `source-base/` tree, artifact-backed recovered source, exact compiled output and engineering notes.
- `PROVENANCE.md` — Diagnostic 1 provenance.
- `scripts/` — materializers/reproducibility helpers for preserved artifacts.

## Source provenance policy

Do not rewrite old release history and do not invent source commits.

The 2026-08-22 package reports `build=93be8aa`, but that identifier is not currently resolvable in `melspixel/Kanki` and the uploaded package does not carry the original C source tree. For that release:

- the compiled package is preserved byte-for-byte;
- `source-base/` carries the complete known source lineage;
- readable scripts plus embedded renderer CSS/JavaScript are recovered exactly into `recovered-source/`;
- `SOURCE_STATUS.md` records what is and is not exact.

If the missing original source becomes available later, add it as a new exact-source record rather than replacing the artifact-backed release history.
