# Kindle native platform layer

This directory contains source-owned native processes that run on Kindle/PW6. It is the platform implementation, not a collection of unrelated mini-projects.

## Components

- `kanki_device.c` — GTK2/WebKit application shell, reviewer lifecycle, navigation and native controls.
- `kanki_sync_cli.c` — collection-exclusive sync process.
- `kanki_diag_server.c` — bounded loopback renderer diagnostics service.
- `kanki_raise.c` — existing-instance/reactivation helper.
- `audio/` — loopback audio service and Kindle-native playback support.

## Platform boundaries

- Runtime UI libraries come from Kindle userspace and are feature-detected where appropriate.
- Lab126 WebKit CSS-pixel/full-content-zoom behavior must be used instead of synthetic viewport rewriting.
- Review and sync must not own the collection concurrently.
- Device code must never delete or replace `/mnt/us/anki_data`.
- RAnki is not a runtime dependency.

Device executables are assembled into the package by `tools/build_kindle_package.sh`.
