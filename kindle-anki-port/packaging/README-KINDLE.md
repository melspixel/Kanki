# Kindle Anki Port

This package contains the PW6 ARM hard-float runtime for the source-driven
Kindle Anki reviewer port.

## Install layout

Copy the archive contents to the Kindle USB root so these paths exist:

- `/mnt/us/extensions/kindle-anki-port/`
- `/mnt/us/documents/Kindle Anki.sh`
- `/mnt/us/documents/Kindle Anki Sync.sh`

User data is stored separately under `/mnt/us/anki_data/` and is never bundled
with the release package. Copy your collection and media there only after
backing them up.

`config.example.ini` is a template only. Do not place sync credentials in a
redistributable archive.

The build provenance is recorded in `BUILD.json`, and `MANIFEST.sha256` covers
every file shipped inside the extension directory.
