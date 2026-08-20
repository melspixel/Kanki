# Install, upgrade and rollback

Kanki rewrite installs beside the historical RAnki/Kanki experiment. It does not overwrite `/mnt/us/extensions/ranki` and never deletes `/mnt/us/anki_data`.

## Clean device test

1. Back up `/mnt/us/anki_data/collection.anki2` and the existing `config.ini`.
2. Extract the release ZIP at the Kindle USB/MTP storage root. It creates:
   - `/mnt/us/extensions/kanki/`
   - `/mnt/us/documents/shortcut_kanki*.sh`
3. Do not copy individual files over an older rewrite build. Replace the whole `/mnt/us/extensions/kanki` directory so `MANIFEST.sha256` remains authoritative.
4. Launch `shortcut_kanki.sh`.
5. Run `shortcut_kanki_sync.sh` only while Kanki is closed.

The first sync migrates only `hkey` and `endpoint` from an existing `/mnt/us/extensions/ranki/config.ini` when the rewrite has no `config.ini`. It does not copy logs, scaling values or other settings.

## Full-sync decision

A normal sync that requires a forced direction exits with code 75 and writes a redacted message to `kanki.log`. After checking the desktop collection, run exactly one of:

- `shortcut_kanki_full_upload.sh` — replace AnkiWeb with this Kindle collection.
- `shortcut_kanki_full_download.sh` — replace this Kindle collection with AnkiWeb.

## Rollback

Close Kanki, rename or delete `/mnt/us/extensions/kanki`, and launch the previous `/mnt/us/extensions/ranki` installation. The rewrite and previous client share `/mnt/us/anki_data`; no rollback step should delete that directory.

## Integrity

Every launcher checks `MANIFEST.sha256` before running. A partial or mixed-version copy is rejected instead of starting with incompatible components.
