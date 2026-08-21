# Resume Kanki rewrite from zero context

This is the first file to read when taking over the `rewrite-v1` work. The goal is that a maintainer can resume the project without chat history, local scratch files, or undocumented commands.

## 1. Authoritative state

- Repository: `melspixel/Kanki`
- Active implementation branch: `rewrite-v1`
- Integration PR: `#10` (`rewrite-v1` -> `main`), intentionally kept Draft
- Closure tracker: issue `#11`
- `main` remains the last accepted legacy line until the rewrite passes hardware acceptance
- Target device: Kindle Paperwhite 12th generation / PW6, ARMv7 hard-float
- Production Anki core: pinned Anki 26.08.1 gitlink under `third_party/anki`

Never infer completion from a compile, a screenshot, or an old green job. Issue #11 plus evidence attached to the release commit is the closure record.

## 2. Current architectural invariants

These are design constraints, not implementation suggestions:

1. RAnki is reference-only. The rewrite must not execute or patch the RAnki binary.
2. No `LD_PRELOAD` backend redirection.
3. No hard-coded 420px logical viewport, media-query rewriting, or global zoom cap.
4. Kindle DPI uses feature-detected Lab126/WebKit CSS-pixel/full-content-zoom behavior when available.
5. The reviewer owns one persistent WebView and one persistent `#qa` document. Card changes update content; they do not recreate the whole browser page.
6. Anki access goes through semantic typed bridge functions. No numeric protobuf service/method IDs are allowed in application code.
7. Card compatibility is deck-agnostic. Never add selectors or behavior for COCA, a specific note type, a specific dictionary template, or a specific user's deck.
8. Audio controls may be constrained; unrelated SVG/images must remain untouched.
9. Sync must not race a second collection owner. Reviewer and sync collection lifetimes are explicit.
10. `/mnt/us/anki_data` is user data. Install, upgrade, rollback, diagnostics and uninstall must never delete or replace it.
11. New rewrite installs under `/mnt/us/extensions/kanki`, separate from legacy `/mnt/us/extensions/ranki`.
12. Release artifacts are self-identifying and manifest-verified. Mixed component versions must be rejected, not tolerated.

If a proposed fix violates any invariant above, stop and redesign it.

## 3. Source map

### Core/domain

- `crates/kanki-domain/` — deterministic review/deck state and shared types
- `crates/kanki-backend/` — application-facing backend abstractions
- `crates/kanki-renderer/` — reviewer packet/rendering policy
- `crates/kanki-platform/` — platform boundary
- `crates/kanki-app/` — host/self-test executable

### Anki integration

- `bridge/anki_bridge.rs` — semantic review/deck/render bridge compiled into pinned Anki
- `bridge/sync_bridge.rs` — semantic sync bridge
- `bridge/kanki_bridge.h`, `bridge/kanki_sync_bridge.h` — C ABI consumed by Kindle executables
- `bridge/smoke.c` — ABI/integration smoke harness

### Kindle native layer

- `device/kanki_device.c` — GTK2/WebKit application and lifecycle
- `device/kanki_sync_cli.c` — sync process
- `device/kanki_raise.c` — existing-instance reactivation helper
- `device/audio/kanki_audio_server.c` — loopback audio service

### Reviewer/device assets

- `assets/device/` — deck/sync/reviewer shell pages
- `assets/reviewer/reviewer.js` — persistent `#qa`, script execution, AV/review protocol
- `assets/reviewer/reviewer.css` — minimal reviewer-owned CSS only
- `assets/reviewer/css_compat.js` — deterministic CSS source compatibility transform
- `assets/reviewer/css_runtime.js` — old-WebKit runtime compatibility behavior

### Packaging/operations

- `scripts/kanki-launch.sh` — launcher and component verification
- `scripts/kanki-sync.sh` — sync lifecycle
- `scripts/kanki-report.sh` — redacted diagnostic bundle
- `packaging/` — config example and Kindle-home shortcuts
- `.github/workflows/package.yml` — canonical installable package recipe

### References

- `third_party/anki` — production core pin
- `third_party/kindle-sdk` — Kindle toolchain/system reference pin
- `third_party/ranki-reference` — historical behavior reference only
- `third_party/audiobook-koplugin` — pinned native Kindle GStreamer reference/helper source

## 4. Test gates and canonical workflows

Use the workflows as executable build documentation. Do not maintain a separate hidden local recipe.

- `.github/workflows/actions-probe.yml` — minimal runner/account/repository execution probe; no product dependencies
- `.github/workflows/ci.yml` — Rust workspace, policy, reviewer contract, host self-test, ARM scaffold
- `.github/workflows/anki-bridge.yml` — typed Anki host bridge/integration
- `.github/workflows/anki-bridge-arm.yml` — typed Anki ARMHF build/ABI
- `.github/workflows/device.yml` — native Kindle device shell
- `.github/workflows/audio.yml` — audio service/helper
- `.github/workflows/css-compat.yml` — legacy WebKit CSS compatibility corpus
- `.github/workflows/package.yml` — final ARMHF package, manifest and ABI gate

`docs/TESTING.md` defines Gates A-E. Gate E requires the real PW6.

## 5. Current blocker at handoff checkpoint

The Actions failure has been isolated from Kanki source.

On 2026-08-21, a deliberately minimal PR workflow named **Actions runner probe** was added. It uses `ubuntu-latest` and has one shell step that only prints the date, `uname`, runner OS and runner architecture. On commit `e3f2abb42bcaca385968b8146751ebbeda269201`, probe run `32469010279` completed `failure`; its only job (`probe`, job `96731662061`) reported `steps = null` and no job log. The normal Kanki workflows failed in the same pre-step manner on that commit.

Therefore the immediate blocker is outside product source execution. Do **not** change Kanki code or workflow build commands to repair these zero-step failures.

First action when resuming:

1. inspect PR #10 current head;
2. inspect the **Actions runner probe** for that head;
3. if the probe has real steps, resume normal CI diagnosis;
4. if the probe still has `steps = null`, inspect GitHub repository/account Actions availability before changing source. In particular check repository Actions policy and, because this is a private repository using GitHub-hosted runners, the account's Actions minutes/billing/budget state. GitHub blocks hosted-runner use when applicable quota/budget/payment conditions prevent additional usage;
5. after any account/repository fix, rerun the probe first;
6. only when the probe enters its `Runner started` step should normal Kanki workflows be treated as actionable source/build failures;
7. then fix the first real failing step only and rerun the narrow workflow.

Do not shotgun-edit seven workflows merely because seven zero-step jobs are red.

## 6. Local/CI reproduction sequence

When a normal runner or equivalent Linux environment is available, use this order:

```sh
# Repository policy and formatting
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
python3 tools/check_policy.py

# Host unit/integration shell
cargo test --workspace
cargo run -p kanki-app -- --self-test

# Reviewer contracts (after installing the pinned jsdom used by CI)
node tests/renderer_contract.test.cjs
node tests/css_compat.test.cjs
```

For Anki and ARMHF work, follow the corresponding workflow verbatim rather than reconstructing commands from memory. The package workflow is the canonical source for toolchain flags, source pins, exported symbols, ABI gates and ZIP layout.

## 7. Evidence rules

For every closed item in issue #11, attach or reference evidence from the same commit:

- exact commit SHA;
- workflow/run name;
- relevant artifact/log;
- target architecture;
- for rendering: fixture name and measured contract result;
- for hardware: device firmware, operation performed and result;
- for sync: desktop integrity/reopen result;
- for privacy: diagnostic bundle inspection result.

Never close a gate using a green result from an older source commit after behavior-changing code has landed.

## 8. PW6 acceptance order

Do not begin hardware acceptance until host + bridge + ARMHF + package gates are green on the exact candidate commit.

On PW6:

1. back up the collection;
2. clean-install into `extensions/kanki` without touching `extensions/ranki` or `anki_data`;
3. capture build identity and system fingerprint;
4. verify deck tree and collapse persistence;
5. verify question -> answer -> Again/Hard/Good/Easy, bury, restart;
6. run renderer corpus including representative original APKG decks without modifying them;
7. verify long-card scrolling;
8. verify AirPods audio and repeated replay;
9. verify normal sync, restart, then desktop Anki integrity;
10. verify full-sync decision paths separately;
11. verify back/exit, duplicate launch, sleep/wake and USB/MTP lifecycle;
12. generate diagnostic ZIP and inspect for credentials/private database content;
13. verify rollback while leaving `anki_data` untouched.

Any failure reopens the relevant gate. Do not compensate by editing the deck.

## 9. Release/merge rule

PR #10 remains Draft and issue #11 remains open until all applicable Gates A-E have same-commit evidence. Only then:

1. freeze a release candidate commit;
2. rebuild the installable ZIP from CI;
3. record ZIP SHA-256 and component pins;
4. complete PW6 acceptance against that exact ZIP;
5. update `STATUS.md`, `HANDOFF.md`, issue #11 and release notes;
6. mark PR ready, merge to `main`, and tag the accepted source point.

## 10. Things that must never be hidden in chat

Before ending any development session, commit/update:

- `docs/STATUS.md` — what is implemented, verified, failing and next;
- issue #11 — closure evidence/checklist state;
- an ADR if architecture/invariants changed;
- `docs/HANDOFF.md` if build/release/diagnostic procedures changed;
- this file if the resume entry point or blocker changed.

A future maintainer should need the repository and GitHub history only.