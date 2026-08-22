# RankiRefresh

RankiRefresh is a preserved, buildable subproject snapshot of the Kanki/RAnki refresh line used for the Anki 26.08 + Kindle renderer diagnostics experiment.

This directory is intentionally self-contained at the project level rather than a collection of patch fragments.

## Layout

- `source/` — the complete source tree for the Diagnostic 1 snapshot, preserving its original repository structure (`.github/`, `src/`, `scripts/`, `tools/`, `vendor/`, docs, README, etc.).
- `dist/` — compiled/installable output materialized from the exact retained GitHub Actions artifacts. It contains both the install ZIP and the unpacked `ranki/` runtime tree.
- `PROVENANCE.md` — immutable source/build/artifact identities and the Google Drive turnover copies.
- `scripts/materialize-dist.sh` — reproducible materializer for the compiled Diagnostic 1 result.

## Preserved baseline

The source snapshot is the exact CI merge tree at commit `f178e5e59e001bbf4964760d722fd6b9b10a28f1` (tree `8fb4d25339660e1b82a984f666b2e54d7a45defa`).

The Anki backend is the KindleHF build from the `anki-26.08-backend` line at commit `b872a164c58aa5955975169944a647fdd678e99e`, with official Anki backend ref `26.08` / commit `666c2c64d4a1772c03948f5b667438da63ddaa76`.

Do not treat `source/` as a patch queue. It is a full frozen source snapshot for this baseline. Future RankiRefresh development should branch from this preserved state or add new versioned directories/commits without rewriting provenance.
