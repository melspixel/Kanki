# Compiled outputs

This directory is populated by `.github/workflows/rankirefresh-materialize.yml` from the exact retained Diagnostic 1 GitHub Actions artifacts.

Expected checked-in outputs after materialization:

- `Kanki-Anki26-diagnostics1.zip` — complete installable Ranki/Kanki package with the Anki 26.08 KindleHF backend included.
- `Kanki-Anki26-diagnostics1.sha256` — checksum of the checked-in install ZIP.
- `unpacked/ranki/` — the complete compiled runtime/install tree, including binaries and shared objects; this is intentionally committed so the project does not contain only a binary archive pointer.
- `BUILD_MANIFEST.txt` — source/artifact identities, package checksum, and file sizes.

The large source artifacts are also archived in Google Drive under `GPT周转/RankiRefresh`; GitHub is the canonical structured project copy.
