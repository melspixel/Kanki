# Installed Kindle runtime scripts

Scripts here are copied into `/mnt/us/extensions/kanki` and execute on the Kindle after installation.

- `kanki-launch.sh` — package identity/manifest checks and component lifecycle startup.
- `kanki-sync.sh` — collection-exclusive sync lifecycle.
- `kanki-report.sh` — redacted diagnostic bundle creation.

Developer/build scripts belong in `tools/` instead.

Runtime scripts must preserve the `/mnt/us/anki_data` safety boundary, fail explicitly on missing required components/diagnostics, and refuse mixed package identities rather than silently continuing.
