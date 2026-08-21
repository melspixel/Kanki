# Package-facing files

This directory contains install-facing static files used by the canonical package builder, such as example configuration and Kindle-home shortcuts.

It does **not** own compilation or ZIP assembly logic. `tools/build_kindle_package.sh` is the canonical package recipe and is responsible for copying these files into the final install tree, generating build identity, manifest and ABI evidence.

Never place user collection data or `config.ini` containing credentials in versioned package inputs.
