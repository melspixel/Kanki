# Kanki — independent Kindle Anki port branch

This branch contains two code histories because it was created from the original Kanki repository without deleting the existing main-branch project. The **active independent desktop-Anki → Kindle PW6 port** lives under:

```text
kindle-anki-port/
```

Start here:

- `kindle-anki-port/HANDOFF.md` — authoritative continuation and release state;
- `kindle-anki-port/PROGRESS.md` — current gate matrix;
- `kindle-anki-port/docs/VM_BUILD_20260821.md` — validated VM build evidence;
- `kindle-anki-port/docs/TEST_ENVIRONMENT.md` — host/ARMHF/QEMU/device test design;
- `kindle-anki-port/CODEX_COORDINATION.md` — local-host / hardware collaboration boundary.

## Independent-port architecture

The port pins official Anki 26.08.1 (`e5a6fbe27fdd4d57d5f712191b4a753032e57853`) and keeps Anki's Rust backend authoritative for collection, scheduling, rendering, typed-answer comparison, media and sync. A narrow named `kap_*` C ABI connects that backend to a Kindle GTK2/WebKitGTK1 host, persistent ES5 reviewer, native audio worker and native sync worker.

The independent port **does not use Ranki, `rewrite-v1`, `LD_PRELOAD`, or historical card-template patch runtimes as production dependencies**.

The root-level `src/`, `scripts/`, `tools/`, `docs/` and legacy `Build Kanki package` workflow belong to the older compatibility-layer project retained from the repository's main history. They are not inputs to `Kindle-Anki-Port-PW6-armhf.zip`. On this branch the legacy workflow is excluded from pushes so it cannot be mistaken for the independent-port release build.

## Build entry point

The independent port is built from ordinary source files in `kindle-anki-port/`. `.github/workflows/kindle-anki-port.yml` is the reproducibility definition; iterative development builds run in the VM while GitHub Actions quota is unavailable.

Do not treat a locally produced ZIP as a release. Release completion is recorded only in `kindle-anki-port/HANDOFF.md` after canonical-source rebuild, ARMHF/ABI/package gates, exact-rootfs QEMU smoke, durable GitHub artifact persistence, and separate PW6 hardware acceptance.
