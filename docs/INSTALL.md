# Install, upgrade and rollback

Kanki rewrite installs beside the historical RAnki/Kanki experiment. It does not overwrite `/mnt/us/extensions/ranki` and never deletes `/mnt/us/anki_data`.

## Clean device test

1. Back up `/mnt/us/anki_data/collection.anki2` and the existing `config.ini`.
2. Extract the release ZIP at the Kindle USB/MTP storage root. It creates:
   - `/mnt/us/extensions/kanki/`
   - `/mnt/us/documents/shortcut_kanki*.sh`
3. Do not copy individual files over an older rewrite build. Replace the whole `/mnt/us/extensions/kanki` directory so `MANIFEST.sha256` remains authoritative.
4. Launch `shortcut_kanki.sh`.
5. Use the in-app **Sync** page for normal sync. The standalone `shortcut_kanki_sync.sh` remains available, but only run it while Kanki is closed.

If Kanki is already running but hidden behind the Kindle system UI, launching `shortcut_kanki.sh` again does not start a second instance. The launcher asks the existing X11 window to raise and take focus instead.

The first sync migrates only `hkey` and `endpoint` from an existing `/mnt/us/extensions/ranki/config.ini` when the rewrite has no `config.ini`. It does not copy logs, scaling values or other settings.

## Full-sync decision

A normal sync that requires a forced direction reports that state in the in-app Sync page. Choose exactly one direction only after checking the desktop collection:

- **Full Upload** — replace AnkiWeb with this Kindle collection.
- **Full Download** — replace this Kindle collection with AnkiWeb.

The equivalent standalone shortcuts are `shortcut_kanki_full_upload.sh` and `shortcut_kanki_full_download.sh`; use them only while Kanki is closed.

## Returning after Kindle settings

Opening a Kindle system surface such as Bluetooth settings can cover the Kanki window without terminating it. Re-launch `shortcut_kanki.sh`; the existing Kanki window should be raised. If that fails, inspect `/mnt/us/extensions/kanki/kanki.log` for a `kanki-raise` diagnostic instead of repeatedly launching new copies.

## Rollback

Close Kanki, rename or delete `/mnt/us/extensions/kanki`, and launch the previous `/mnt/us/extensions/ranki` installation. The rewrite and previous client share `/mnt/us/anki_data`; no rollback step should delete that directory.

## Integrity

Every launcher checks `MANIFEST.sha256` before running. A partial or mixed-version copy is rejected instead of starting with incompatible components.
