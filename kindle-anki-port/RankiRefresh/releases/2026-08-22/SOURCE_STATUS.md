# Source status — release 2026-08-22

This release deliberately separates exact source, recovered source and binary-only provenance.

## Exact, complete source available

`source-base/` is the full preserved Diagnostic 1 source tree, Git tree:

`8fb4d25339660e1b82a984f666b2e54d7a45defa`

It contains the complete repository structure used by that preserved baseline (`.github/`, `src/`, `scripts/`, `tools/`, `vendor/`, docs and build workflow), not a set of diff fragments.

## Exact source-readable material from this release

The materialization workflow copies or extracts these bytes from the user-supplied 2026-08-22 package:

- `ranki.sh`
- `kindle-system-fingerprint.sh`
- `config.ini.default`
- `KANKI_BUILD.txt`
- embedded `KANKI_REVIEWER_CSS` from `libkanki-webkit-armhf.so`
- embedded `KANKI_COMPAT_JS` from `libkanki-webkit-armhf.so`
- embedded native/fallback scale snippets

Those files live under `recovered-source/` and are byte-exact representations of the readable code/data shipped inside the release.

## Source that is not present in the supplied artifact

The uploaded ZIP does **not** contain the original C build sources for the new WebKit shim/backend redirect, nor a Git repository. `KANKI_BUILD.txt` reports `build=93be8aa`, but `93be8aa` is not resolvable as a commit in `melspixel/Kanki` at publication time.

Therefore the repository does not claim that `source-base/` is the exact source of every new binary, and it does not fabricate a synthetic commit matching `93be8aa`.

Binary truth for this release is preserved under `dist/unpacked/ranki/`, including:

- `libkanki-webkit-armhf.so`
- `libkanki-webkit-armel.so`
- `libkanki-backend-redirect-armhf.so`
- `libanki-26.08-armhf.so`
- `ranki-armhf` / `ranki-armel`
- audio/player helpers

## Future provenance repair

If the original source tree behind `build=93be8aa` is recovered later, add it as a new exact-source directory with its own commit/tree identity and compare it against the already preserved binaries. Do not rewrite or delete this artifact-backed record.
