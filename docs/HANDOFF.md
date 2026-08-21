# Maintainer handoff

A maintainer must be able to reproduce, diagnose, test and release Kanki without reconstructing chat history.

**Start here when taking over:** `docs/RESUME.md`.

`RESUME.md` is the operational entry point; this document defines the permanent handoff contract.

## Handoff source of truth

The repository, PR #10, issue #11, committed documentation and CI artifacts are authoritative. Chat logs, local scratch directories and manually assembled ZIPs are not.

Current implementation line:

- `main` — last hardware-accepted legacy line;
- `rewrite-v1` — active source-owned replacement;
- PR #10 — integration PR, kept Draft until closure;
- issue #11 — evidence-backed closure tracker.

Before taking over, read in order:

1. `docs/RESUME.md`
2. `docs/STATUS.md`
3. `docs/ARCHITECTURE.md`
4. `docs/TESTING.md`
5. `docs/INSTALL.md`
6. ADRs under `docs/adr/`
7. issue #11 and PR #10 history

## Source-of-truth pins

The gitlinks under `third_party/` are authoritative. The production core is the pinned Anki source; RAnki is reference-only.

Updating Anki requires a dedicated PR that:

1. changes the Anki gitlink;
2. records upstream release notes, schema/proto/API changes and migration risk;
3. recompiles the semantic bridge rather than preserving obsolete numeric dispatch assumptions;
4. runs host, cross, ABI, renderer and device acceptance suites;
5. updates the compatibility matrix and build identity;
6. never changes application behavior through opaque numeric service IDs.

No dependency may be silently changed from `latest` behavior into a release artifact without recording the resolved source/version in build identity.

## Architectural invariants

The permanent invariants are enumerated in `docs/RESUME.md`. In particular:

- no runtime patching of RAnki;
- no `LD_PRELOAD` backend redirect;
- no hard-coded Kindle logical viewport/media-query rewrite;
- persistent single-WebView `#qa` reviewer lifecycle;
- typed semantic Anki bridge;
- deck-agnostic renderer compatibility only;
- explicit collection ownership across review/sync;
- `anki_data` is never part of install/upgrade/rollback mutation;
- release components must refuse mixed build identities.

Architecture changes require an ADR before or with the implementation change.

## Build identity

Every installable package must contain and expose:

- semantic version;
- Kanki git commit;
- Anki git commit;
- Kindle SDK/toolchain reference commit;
- native audio helper/reference commit where applicable;
- target architecture;
- minimum required GLIBC/GCC symbol versions;
- reviewer protocol version;
- SHA-256 manifest of packaged files;
- release gate status.

The launcher must log these values before opening the collection and must refuse to run when component build IDs disagree.

The package workflow is the canonical definition of package layout and ABI checks. A developer-created ZIP is never a release artifact.

## Build and CI ownership map

- `.github/workflows/ci.yml` — host workspace, policy, reviewer contract, self-test, ARM scaffold
- `.github/workflows/anki-bridge.yml` — typed Anki host integration
- `.github/workflows/anki-bridge-arm.yml` — typed Anki ARMHF build and ABI
- `.github/workflows/device.yml` — Kindle GTK/WebKit native shell
- `.github/workflows/audio.yml` — loopback audio service and native player
- `.github/workflows/css-compat.yml` — old-WebKit generic CSS compatibility
- `.github/workflows/package.yml` — final self-identifying installable package

If CI and documentation disagree, fix one immediately; do not create a hidden alternative build recipe.

## Diagnostic bundle

A single command must create a redacted ZIP containing enough information to diagnose a device without another custom build:

- build identity and manifest status;
- firmware/system fingerprint without serial/account/Wi-Fi identifiers;
- application and component startup logs;
- Lab126/WebKit capability and pixel-density report;
- bounded reviewer/render metrics;
- backend-rendered card HTML and final reviewer packet for a bounded number of cards;
- audio pipeline capability/result data;
- sync state/error category without credentials.

It must not contain:

- AnkiWeb auth tokens;
- account identifiers;
- the collection database;
- unbounded user note content;
- Wi-Fi credentials or device serial identifiers.

Diagnostic directory/bundle creation failure is an explicit error. It must never be swallowed with `|| true` and then reported as enabled.

## Test evidence and closure

`docs/TESTING.md` defines Gates A-E. Issue #11 records closure. A checkbox may only close with evidence from the same candidate commit or with an explicit reason why a commit-independent hardware fact applies.

Evidence records should include:

- Kanki commit SHA;
- workflow/run or hardware test identifier;
- architecture/device firmware;
- exact test/fixture;
- artifact/log location;
- result and remaining limitation.

A green build is not hardware acceptance. A device screenshot is not backend/sync acceptance. Old green runs cannot be inherited across behavior-changing commits.

## Branch/release policy

- `main`: last hardware-accepted release.
- `rewrite-v1`: active replacement until issue #11 closes.
- feature branches: focused changes with matching tests/ADR updates.
- tags: accepted source points only.
- generated ZIPs: CI/package workflow only.

PR #10 stays Draft until host, Anki bridge, ARMHF, renderer/package and PW6 acceptance evidence all belong to the release candidate.

## Session-end protocol

Before handing the project to another maintainer or ending a substantial implementation session:

1. update `docs/STATUS.md` with implemented/verified/failing/next state;
2. update issue #11 with new evidence or reopened gates;
3. update `docs/RESUME.md` if the current blocker or next action changed;
4. add/update an ADR for architecture changes;
5. ensure the active branch has no important uncommitted-only instructions;
6. link the exact failing workflow/run rather than saying only "CI is red";
7. do not claim an installable package exists unless its manifest/ABI package workflow succeeded.

## Definition of handoff-ready

The project is continuously handoff-ready when all of the following are true, even before release:

- `RESUME.md` tells a new maintainer what to do first;
- `STATUS.md` matches the current branch rather than the first bootstrap commit;
- no critical knowledge exists only in chat;
- dependencies and source pins are visible;
- build/test commands live in repository workflows/docs;
- architecture decisions and forbidden shortcuts are recorded;
- active blockers are explicit;
- device rollback and data boundaries are documented;
- test corpus and expected behavior are committed;
- known limitations are listed, not hidden in logs.

Release-ready additionally requires issue #11/Gate E completion on the target PW6.