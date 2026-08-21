# Local Codex handoff — Kanki rewrite

This is the handoff document for a local Codex instance taking over the Kanki rewrite on a developer machine. It is intentionally operational: it tells you what is authoritative, what is historical clutter, what may be reorganized, what must not change, and how to obtain real compiler/test evidence without depending on GitHub Actions.

## 1. Mission

Finish the source-owned Kindle Anki client so it can replace the historical patched RAnki/Kanki line without deck-specific fixes.

The target is a Kindle Paperwhite 12th generation / PW6 running Amazon's published userspace. The client must:

- use the real pinned Anki 26.08.1 Rust backend for scheduling, rendering, collection and sync semantics;
- use Kindle's native GTK2/WebKit/Lab126 capabilities instead of synthetic viewport tricks;
- preserve ordinary Anki card HTML/CSS/JS semantics as closely as the old WebKit permits;
- provide AirPods/Bluetooth audio through Kindle-native audio infrastructure;
- be diagnosable without requiring a custom build for every rendering issue;
- never require per-deck modification for normal decks;
- remain safe for `/mnt/us/anki_data`;
- be reproducible and handoff-ready at every stage.

Do not optimize for “it works on one COCA card”. Optimize for architectural parity with Anki and predictable behavior on Kindle.

## 2. Authoritative repository state

Repository: `melspixel/Kanki`

- `main`: last accepted legacy/patched line. Treat as historical fallback until rewrite acceptance.
- `rewrite-v1`: active rewrite implementation.
- PR #10: `rewrite-v1 -> main`, intentionally Draft.
- issue #11: verification/closure authority.
- root `AGENTS.md`: mandatory automated-agent rules.

Source pins under `third_party/` are intentional gitlinks:

- `third_party/anki` → Anki 26.08.1, commit `e5a6fbe27fdd4d57d5f712191b4a753032e57853`;
- `third_party/kindle-sdk` → Kindle SDK/system reference;
- `third_party/ranki-reference` → historical RAnki reference only;
- `third_party/audiobook-koplugin` → native Kindle GStreamer reference/helper.

Never silently float these dependencies.

## 3. Read these before editing

Read in this order:

1. `AGENTS.md`
2. `docs/STATUS.md`
3. `docs/ARCHITECTURE.md`
4. `docs/ANKI_DESKTOP_PARITY.md`
5. `docs/TESTING.md`
6. `docs/LOCAL_BUILD.md`
7. `docs/HANDOFF.md`
8. `docs/adr/`
9. issue #11
10. PR #10 history

Treat documentation as a map, not unquestionable truth. If source and docs disagree, determine which is current from commit history and tests, then fix the docs in the same work session.

## 4. Current repository audit

The repository is not multiple independent products, but it currently **looks like several overlapping projects** because rewrite work accumulated as separate layers and experiments.

Current top-level responsibilities are:

- `crates/` — Rust application/domain abstractions;
- `bridge/` — semantic C ABI embedded into the pinned Anki Rust backend;
- `device/` — source-owned Kindle native C executables;
- `assets/` — device pages, persistent reviewer runtime and scoped MathJax adapter;
- `scripts/` — scripts that run on the Kindle after installation;
- `tools/` — developer/build/test tooling;
- `packaging/` — install-facing config and Kindle-home shortcuts;
- `tests/` — source/renderer/diagnostic contracts;
- `third_party/` — pinned references/dependencies;
- `docs/` — status, architecture, build, parity, testing, handoff and ADRs;
- `.github/workflows/` — CI executors.

That monorepo split is defensible. The main sources of confusion are elsewhere:

### 4.1 Too many historical branches

Observed experimental/history branches include, in addition to `main` and `rewrite-v1`:

- `test2-ci`
- `test3-native-audio`
- `test4-audio-ui`
- `test4-final`
- `test5-coca-layout`
- `anki-26.08-backend`
- `refactor-anki-compat`
- `renderer-adaptive-v2`
- `dropin-native-renderer`
- `desktop-anki-kindle-port`
- `kanki-next-bootstrap`
- `kindle-anki-port`
- `kindleanki-v1-closure`

There may be others. These branches make GitHub look like it contains many projects when most are historical experiments.

Do not delete them blindly. First preserve their tips as archival tags or record a branch→commit map, verify that no unmerged source is required by `rewrite-v1`, then delete obsolete branches using normal Git/GitHub tooling. The intended long-term branch set is small:

- `main`
- one active integration branch until release (`rewrite-v1`)
- short-lived focused feature branches

### 4.2 Transitional developer patch scripts

`tools/` currently includes files such as:

- `patch_sync_ui.py`
- `patch_type_answer_ui.py`

These names strongly suggest transitional source-edit helpers created during rapid iteration. Audit whether the changes they apply are already integrated into canonical source files. If yes, remove them. If they are still required, either:

- convert them into deterministic build-generation steps with tests and documentation; or
- move them under an explicitly historical/migration-only directory and explain why they exist.

A release build must not depend on an undocumented “patch this file after checkout” sequence.

### 4.3 CI workflow sprawl

`.github/workflows/` currently contains separate host, Anki bridge, ARM bridge, audio, device, CSS, package and Actions-probe workflows.

Component workflows were useful while discovering the architecture, but they duplicate setup and make the project look more fragmented than it is. Do **not** collapse them before real local baselines exist. After the local build is healthy, consolidate toward a smaller model, for example:

- `ci.yml` — host/source/unit/renderer contracts;
- `kindle.yml` — typed Anki ARMHF + native device/audio/diagnostics + ABI checks;
- `package.yml` — invokes the canonical package script and uploads the artifact;
- `actions-probe.yml` — temporary only while hosted runner infrastructure is broken; remove once no longer useful.

Build logic belongs in versioned scripts under `tools/`, not copied into YAML.

### 4.4 Documentation overlap

The current docs are useful but overlap:

- `RESUME.md`
- `STATUS.md`
- `HANDOFF.md`
- `LOCAL_BUILD.md`
- `TESTING.md`
- `ANKI_DESKTOP_PARITY.md`
- `ARCHITECTURE.md`

Do not delete information during cleanup. First make `docs/README.md` an index, then define one owner per question:

- What is happening now? → `STATUS.md`
- I have zero context, where do I start? → `CODEX_HANDOFF.md` / `RESUME.md`
- Why is it designed this way? → `ARCHITECTURE.md` + ADRs
- How do I build locally? → `LOCAL_BUILD.md`
- How do I prove it works? → `TESTING.md` + issue #11
- What must match desktop Anki? → `ANKI_DESKTOP_PARITY.md`
- How do maintainers operate/release? → `HANDOFF.md`

After this ownership is clear, deduplicate repeated paragraphs rather than deleting whole documents impulsively.

### 4.5 Production path vs scaffolding

The Rust workspace contains five crates while the actual Kindle shell is native C and the production Anki backend bridge is injected into pinned Anki. Audit whether each crate is used by the real package path or is only bootstrap scaffolding:

- `kanki-domain`
- `kanki-backend`
- `kanki-renderer`
- `kanki-platform`
- `kanki-app`

Do not remove them merely because the device is C. For each crate, establish one of:

- production dependency;
- host model/test oracle;
- planned future dependency with an active milestone;
- obsolete scaffold.

Only the final category should be removed.

## 5. Recommended target layout

Do **not** perform a mass rename as the first task. First get a local green baseline. Once behavior is stable, reorganize toward clear ownership. A reasonable target is:

```text
Kanki/
├── AGENTS.md
├── README.md
├── Cargo.toml
├── crates/                    # Rust domain/host components
├── integrations/
│   └── anki/                  # current bridge/
│       ├── src/
│       ├── include/
│       └── smoke/
├── platform/
│   └── kindle/                # current device/
│       ├── app/
│       ├── sync/
│       ├── diagnostics/
│       └── audio/
├── ui/                        # current assets/
│   ├── shell/
│   └── reviewer/
├── runtime/                   # current scripts/
├── build/                     # canonical build/toolchain/docker scripts
├── packaging/
├── tests/
│   ├── host/
│   ├── bridge/
│   ├── renderer/
│   └── package/
├── third_party/
├── docs/
│   ├── README.md
│   ├── STATUS.md
│   ├── CODEX_HANDOFF.md
│   ├── architecture/
│   ├── development/
│   └── adr/
└── .github/workflows/
```

This target is advisory. Prefer fewer moves if existing paths are already clear to maintainers. The important outcome is ownership and removal of historical ambiguity, not cosmetic renaming.

## 6. Non-negotiable architecture

Do not violate these during cleanup or debugging:

1. RAnki is reference-only; never a runtime dependency.
2. No `LD_PRELOAD` redirection.
3. No synthetic 420px logical viewport, broad media-query rewrite, or global typography scaling.
4. Kindle CSS pixels use feature-detected Lab126/WebKit behavior.
5. Reviewer uses one persistent WebView and persistent `#qa`.
6. Anki application API is semantic/typed, not numeric protobuf dispatch.
7. No deck-specific selectors/logic.
8. Do not globally size arbitrary SVG/images to repair audio controls.
9. Review and sync collection ownership must be explicit and non-racing.
10. Never mutate/delete `/mnt/us/anki_data` in install/upgrade/rollback/testing code.
11. Rewrite installs to `/mnt/us/extensions/kanki`, not over legacy RAnki.
12. Package identity and manifest mismatch must fail closed.
13. Default diagnostics are bounded and privacy-safe; raw note/card content is opt-in.
14. Toolchains/dependencies are pinned/checksummed.

## 7. Local build is now the primary engineering path

GitHub Actions currently fail before the first job step, including a trivial runner probe. Do not wait for GitHub before compiling.

On macOS, especially Apple Silicon, use:

```sh
git checkout rewrite-v1
git pull --ff-only
git submodule update --init \
  third_party/anki \
  third_party/kindle-sdk \
  third_party/audiobook-koplugin \
  third_party/ranki-reference

bash tools/local_package_docker.sh
```

The Docker path deliberately uses Linux/amd64 because the pinned KindleHF host toolchain is Linux x86-64.

For host-only gates:

```sh
sh tools/run_host_gates.sh
```

For the native typed-Anki ABI and basic disposable-collection smoke:

```sh
sh tools/local_anki_bridge_docker.sh
```

The canonical full package recipe is:

```sh
bash tools/build_kindle_package.sh
```

Do not create another package recipe in local notes or a new workflow.

Expected package evidence directory:

```text
out/local-kindle/
```

Expected primary artifact:

```text
Kanki-rewrite-hw3.zip
```

Do not install a build merely because the ZIP exists. Check package/ABI/manifest gates first.

The package recipe checksum-verifies MathJax through
`tools/install_mathjax.sh` and emits `mathjax-info.txt`. It creates the final
ZIP through the internal `tools/create_reproducible_zip.py` helper and emits
`archive-info.txt`; this helper is not an alternative package recipe.

## 8. First takeover session — exact sequence

Execute this sequence before broad refactoring:

```sh
git checkout rewrite-v1
git pull --ff-only
git status --short
git rev-parse HEAD
git submodule status
```

Then inventory:

```sh
git branch -a
find . -maxdepth 2 -type f | sort
```

Then host baseline:

```sh
sh tools/run_host_gates.sh
```

Then native typed-Anki/disposable-collection smoke:

```sh
sh tools/local_anki_bridge_docker.sh
```

Then full local package:

```sh
bash tools/local_package_docker.sh
```

Capture the **first real failure**, not the last 500 lines. Fix one failure class at a time.

Before changing directory layout, obtain at least:

- a passing or well-understood host baseline;
- a real typed-Anki compilation result;
- a real ARMHF package attempt.

This prevents repository cleanup from hiding product failures.

## 9. Current technical areas that still need verification

Issue #11 is authoritative, but expect work in these areas:

- typed Anki host build and disposable collection integration;
- queue/render/AV/type-answer/answer/bury semantics;
- effective deck-config autoplay and answer-side question-audio replay;
- sync/full-sync/media-sync lifecycle;
- ARMHF Anki library and ABI audit;
- native GTK2/WebKit app launch on PW6;
- Lab126 CSS pixel/full-content zoom on the actual device;
- old-WebKit generic CSS compatibility corpus;
- scripts/images/SVG/audio/cloze/long-card/cardN behavior and MathJax geometry
  on actual Kindle WebKit (the generic host MathJax lifecycle contract passes);
- original COCA and other representative APKGs without modifying them;
- diagnostics directory/metrics/raw-capture limits and privacy;
- clean install, historical upgrade, rollback and duplicate/sleep/USB lifecycle;
- reproducible package and exact artifact SHA;
- PW6 hardware acceptance.

Do not infer hardware success from emulation or source inspection.

## 10. Rendering philosophy

If a card differs from desktop Anki, diagnose in this order:

1. Anki backend render output;
2. Kanki packet transformation;
3. reviewer DOM lifecycle;
4. deck CSS after generic compatibility transform;
5. Kindle WebKit computed style/geometry;
6. Lab126 CSS-pixel/zoom state;
7. device font/media availability.

Do not jump directly to a deck-specific CSS override.

The diagnostics system exists specifically so this chain can be observed.

## 11. Commit discipline during takeover

Use small commits with one purpose. Good examples:

- `build: fix local Anki ARMHF compile`
- `test: add autoplay parity fixture`
- `refactor: remove obsolete type-answer patch helper`
- `docs: reconcile current local-build state`
- `chore: archive obsolete experimental branches`

Avoid commits like `cleanup everything` that mix path moves, renderer changes, backend changes and build changes.

When moving files, use `git mv` so history remains discoverable.

## 12. Session-end handoff protocol

Before stopping work, update repository state so another maintainer can resume without your terminal scrollback:

- `docs/STATUS.md`: exact SHA, what passed, what failed, first actionable error, next command;
- this file if takeover instructions changed;
- `docs/HANDOFF.md` if operating/release procedures changed;
- issue #11 for verified evidence or reopened gates;
- ADR if architecture/invariants changed.

Do not record secrets, AnkiWeb auth keys, account identifiers, device serials or Wi-Fi credentials.

## 13. Definition of “repository cleaned up”

Cleanup is complete when:

- only a small, purposeful set of branches remains;
- every top-level directory has one clear responsibility;
- no production build relies on `patch_*` transition scripts;
- build logic has one canonical implementation callable locally and from CI;
- CI YAML is mostly orchestration, not duplicated build code;
- docs have an index and non-overlapping ownership;
- scaffolding is either used, explicitly labelled, or removed;
- no critical knowledge exists only in old PR branches or chat history;
- `git clone --recursive` + documented commands are sufficient for a new maintainer to reproduce the build/test state.

Repository cleanup is not a release gate substitute. After cleanup, the exact candidate still needs issue #11 evidence and PW6 acceptance.
