# Third-party source/build inputs

RankiRefresh preserves the complete Kanki Diagnostic 1 source tree under `source/`. Some upstream dependencies were intentionally consumed by the frozen build workflow rather than vendored in full.

The frozen workflow is part of `source/` and is the authoritative dependency recipe. Important external inputs include:

- upstream RAnki release package: `https://github.com/crazy-electron/ranki/releases/latest/download/ranki.zip` as resolved by the original 2026-08-20 CI run;
- Kindle native GStreamer helper source from `stradichenko/audiobook.koplugin`, pinned by the workflow to commit `62edf76feb1b7f4af2f01754957e8d57eb3e7d67`;
- koxtoolchain tag `2025.05`;
- miniaudio `0.11.21`;
- official Anki 26.08 backend source, commit `666c2c64d4a1772c03948f5b667438da63ddaa76`, with the Kanki FFI overlay preserved in `source/vendor/anki26/`.

The compiled files resolved from those inputs are checked in under `dist/unpacked/ranki/`, while the installable package is under `dist/`.
