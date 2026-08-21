# Web UI assets

This directory contains source-owned HTML/CSS/JavaScript used by the Kindle application.

- `device/` — deck list, sync page and persistent reviewer shell.
- `reviewer/` — persistent `#qa` runtime, minimal reviewer-owned CSS, generic old-WebKit compatibility and renderer diagnostics client.

Card note-type CSS/HTML remains authoritative. Assets here may provide platform compatibility and semantic reviewer controls, but must not contain named-deck or user-specific layout rules.

Installed asset paths are assembled by `tools/build_kindle_package.sh`.
