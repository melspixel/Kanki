# Kindle Anki Port — Progress and Handoff

Last updated: 2026-08-21

## Canonical project location

- Repository: `melspixel/Kanki`
- Working branch: `kindle-anki-port`
- Branch head at handoff creation: `a5a5a423fa514a5ecce2aed27b670253d0519be8`
- Upstream Anki pin: `e5a6fbe27fdd4d57d5f712191b4a753032e57853` (Anki 26.08.1)

This file is the authoritative continuation point. Update it after every material build, test, packaging, or release change.

## User-required deliverables

1. Full maintainable source tree committed to GitHub, not only archive chunks.
2. Reproducible GitHub Actions build.
3. PW6 ARM hard-float installation archive.
4. SHA-256 checksum, package contents, build provenance, and test report.
5. Final package persisted on GitHub, not only in a temporary chat filesystem.
6. No bundled collection, media, credentials, logs, PID files, or user configuration.
7. No dependency on RAnki, `rewrite-v1`, `LD_PRELOAD`, or prior card-template patch sets.

## Current repository state

The branch currently contains a source archive split into `part-00` through `part-08`, `restore.sh`, and `Kindle-Anki-Port-source.zip.sha256`. The verified archive SHA-256 is:

```text
ac234bb5ca8bdb59fef39dd533880dad708b40c2ba03799c5d147e745f997ffa
```

The archive restores a `kindle-anki-port/` project containing:

- semantic Rust/C ABI adapter over the pinned official Anki backend;
- Kindle GTK/WebKit frontend;
- deck and persistent reviewer web runtime;
- lifecycle and synchronization scripts;
- packaging metadata and architecture/release documentation.

The source directory has not yet been materialized into ordinary GitHub files on this branch. Archive chunks are temporary and must be removed after source-tree materialization.

## Build status

Status: **in progress — no final install package has been accepted or released**.

The existing workflow `.github/workflows/kindle-anki-port.yml` is an early build definition. Before release it must be replaced by the tested build-farm workflow and must:

- initialize the pinned Anki Fluent translation submodules;
- use the Kindle hard-float GCC toolchain consistently;
- compile and test the semantic backend on the host;
- cross-compile `libanki-kindle.so`, `kap-app`, and `kap-audio`;
- audit ABI, exported `kap_*` symbols, and GLIBC requirements;
- assemble, inspect, checksum, and persist the install archive.

## Known engineering risks / next actions

1. Materialize the verified source archive into `kindle-anki-port/` in GitHub.
2. Apply the latest corrected semantic backend, native frontend, audio worker, and injector sources.
3. Add Anki `ftl/core-repo` and `ftl/qt-repo` submodule initialization to CI.
4. Run the host backend test/build gate and fix any API drift against Anki 26.08.1.
5. Run ARMHF cross-build with `arm-kindlehf-linux-gnueabihf-gcc`.
6. Verify `file`, `readelf`, `nm`, dynamic dependencies, and GLIBC ceiling.
7. Add automated package-policy and lifecycle tests.
8. Create a GitHub-hosted final artifact/release and record its immutable URL and SHA-256 below.

## Release record

Not yet released.

When complete, replace this section with:

- release/tag;
- source commit;
- workflow run ID;
- artifact/release asset name;
- exact SHA-256;
- automated test results;
- hardware acceptance status and any remaining device-only checks.

## Integrity rule

Do not mark the project complete merely because a ZIP exists locally. Completion requires a green reproducible build, package audit, GitHub persistence, and this handoff document updated with exact evidence.
