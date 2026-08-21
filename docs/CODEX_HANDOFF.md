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

The following preservation ledger was captured with a read-only
`git ls-remote --heads origin` on 2026-08-21, before deleting any branch.
At capture time `main` was
`f9d2c884a3e191f5975d484675a3283d1bbb4c3d` and `rewrite-v1` was
`48e63674036a370fcfbfd5471ff8ea3ee25b30a7`. The object IDs are the durable
provenance record; a recovery clone must still retain/fetch the corresponding
object or GitHub PR ref. `kindle-anki-port` resumed receiving commits during
retirement and was therefore excluded from deletion; the table retains its
initial captured tip and records the live-ref exception.

| Historical remote branch | Preserved tip SHA | Initial ancestry/content disposition |
| --- | --- | --- |
| `anki-26.08-backend` | `b872a164c58aa5955975169944a647fdd678e99e` | non-ancestor; content audit required |
| `ci-validation` | `54127ee6e21303ba1ba96477dedd467b7b2b5205` | non-ancestor; content audit required |
| `desktop-anki-kindle-port` | `f9d2c884a3e191f5975d484675a3283d1bbb4c3d` | identical to preserved `main` tip |
| `dropin-native-renderer` | `4212ab0054faaf4c6f156835729f69d87500148a` | non-ancestor; content audit required |
| `handoff-codex-cleanup` | `92a7313a2608324616ee140fc030bcc5b31787fb` | temporary non-ancestor; content audit required |
| `kanki-next-bootstrap` | `86dcd09f3a3f34e7669ddd310dc360781a98ed74` | non-ancestor; content audit required |
| `kindle-anki-port` | `afe207d3a771273f75f306c482b65b9cfd8c1bbe` (initial capture) | concurrently active; do not delete until stable and re-audited |
| `kindleanki-v1-closure` | `90dae0fdf57889fc70d4ac447908eee04287394f` | fully contained in `rewrite-v1` |
| `refactor-anki-compat` | `2bc08be6b6cb27c70fff55f2c27fbdc3d1c8a075` | fully contained in `rewrite-v1` |
| `renderer-adaptive-v2` | `0993c13d87819c11ea161d3e3c07c8363552b411` | non-ancestor; content audit required |
| `repo-cleanup-v1` | `b683b9e4ca711d2276d70c28f6364a0d1266b5e2` | temporary non-ancestor; content audit required |
| `test2-ci` | `d656669deb06ed0d068a86f9fbffdabf33914163` | non-ancestor single trigger commit; verify before deletion |
| `test3-native-audio` | `09bc1a13aaf0d26da64c7054fc07aa45ddc9dec7` | fully contained in `rewrite-v1` |
| `test4-audio-ui` | `a7d34dd1aa07cc4a8ad79f79390d48b5e2ea7c35` | fully contained in `rewrite-v1` |
| `test4-final` | `40e3ed3ce4c36a0e6ec92345909ceae563dde53e` | fully contained in `rewrite-v1` |
| `test5-coca-layout` | `1cafa1a754577a79b6d08ccad70a0bcf684ac46b` | fully contained in `rewrite-v1` |

This ledger preserves names and tips but is not permission to discard unique
content. For every non-ancestor branch, inspect its unique commits and tree,
record why required behavior is present or intentionally rejected in
`rewrite-v1`, and only then delete the remote name. These branches make GitHub
look like it contains many products when most are historical experiments. The
intended long-term branch set is small:

- `main`
- one active integration branch until release (`rewrite-v1`)
- short-lived focused feature branches

#### Final retirement audit

The content audit completed on 2026-08-22 against rewrite code point
`8c97be710b3c43f8c485fec040ff1172db997a88`:

- `desktop-anki-kindle-port`, `kindleanki-v1-closure`,
  `refactor-anki-compat`, `test3-native-audio`, `test4-audio-ui`,
  `test4-final` and `test5-coca-layout` have no commits outside
  `rewrite-v1`.
- `test2-ci` adds only `ci-test2.txt`; it contains no product or test logic.
- `ci-validation` changes the historical `src/` audio helper and old workflow.
  Its useful process-group stop behavior is present in
  `device/audio/kanki_audio_server.c` and enforced by
  `tests/audio_source_contract.py`; its ARMEL/static helper recipe is not the
  canonical PW6 ARMHF package path.
- `anki-26.08-backend` is the rejected RAnki runtime redirect experiment. It
  installs a backend shim through `LD_PRELOAD`; the rewrite instead builds the
  fixed Anki source with the semantic `bridge/` ABI and has executable
  host/ARMHF/rootfs evidence.
- `renderer-adaptive-v2`, `kanki-next-bootstrap` and
  `dropin-native-renderer` retain historical firmware research, but their
  branch-side runtime still packages RAnki/redirect shims and the adaptive
  layer hard-codes `LOGICAL_VIEWPORT_PX = 420` while rewriting media queries.
  The accepted Lab126 symbols, persistent reviewer, privacy-bounded
  diagnostics and fixed-firmware audit now live in source-owned
  `device/`, `assets/`, `scripts/` and `tools/audit_pw6_rootfs.sh` without
  those forbidden mechanisms.
- `kindle-anki-port` is a second parallel source/overlay product tree. Its
  semantic boundary, sync-worker and QEMU goals are covered more directly by
  the current pinned-Anki disposable integration, controlled normal/full/media
  sync tests, canonical ARMHF package and authenticated PW6 rootfs audit. No
  separate port tree or split overlay was needed by the audited rewrite.
  However, after that audit the branch resumed receiving GLIBC, protoc,
  rootfs/QEMU, VM-runbook and CI commits. It advanced repeatedly while the
  retirement operation was running (observed through
  `3c0f59d6bc159c86d24748f87677499ed9515bb7`), so it was deliberately
  excluded rather than racing an active writer. Its initial captured tip and
  live remote ref preserve the work. Re-audit all later commits once ownership
  and the tip stabilize; do not import the parallel tree or its workflow
  wholesale, and do not delete the branch or close PR #14 before that audit.
- the useful directory-ownership commits from `repo-cleanup-v1` were
  cherry-picked and corrected for the current build. The two one-shot patch
  tools were independently audited/removed with a policy guard, and the sole
  obsolete Rust scaffold was removed after dependency and host-gate proof.
  `handoff-codex-cleanup` is the superseded subset; neither temporary cleanup
  branch retains required code.

Fifteen static historical/temporary names were deleted atomically on
2026-08-22 with exact-SHA force-with-lease guards after their preserved tips
were rechecked. Superseded PRs #8, #9, #12, #13 and #17 were closed without
merge. `kindle-anki-port` and PR #14 remain temporarily active because of the
concurrent writes above; PR #10 remains the active rewrite PR. The resulting
remote branch set was `main`, `rewrite-v1` and the live exception
`kindle-anki-port`.

### 4.2 Transitional developer patch scripts

The former `tools/patch_sync_ui.py` and
`tools/patch_type_answer_ui.py` were audited against `device/kanki_device.c`,
the persistent reviewer and their executable contracts. Every intended change
is canonical source, and neither script was referenced by a build, test or
workflow. They were removed as obsolete one-shot migrations. The host policy
gate rejects their reintroduction; the release build has no undocumented
“patch this file after checkout” sequence.

### 4.3 CI workflow sprawl

After exact SHA `7a0d83975d7f8180f22abec8cc7596e03622ce66`
passed host, typed-Anki/APKG/sync, two reproducible ARMHF package builds and
the official PW6 rootfs audit, the eight workflows were consolidated to three:

- `ci.yml` invokes `tools/run_host_gates.sh` and the canonical typed-Anki
  Docker executor;
- `package.yml` invokes `tools/build_kindle_package.sh` and uploads the
  SHA-named artifact plus build identity/manifest/archive evidence;
- `actions-probe.yml` remains temporarily isolated while hosted runner
  allocation is broken.

The standalone Anki, ARM bridge, device, audio and CSS workflows were removed;
their useful gates are already owned by the canonical scripts. A separate
`kindle.yml` was not added because it would rebuild the same ARMHF backend,
device, audio and diagnostics objects already covered by the package recipe.
Policy rejects both extra workflow files and direct compiler/test bodies in
YAML. Build logic belongs in versioned scripts under `tools/`.

### 4.4 Documentation ownership

The current docs are useful only if each question has one owner:

- `RESUME.md`
- `STATUS.md`
- `HANDOFF.md`
- `LOCAL_BUILD.md`
- `TESTING.md`
- `ANKI_DESKTOP_PARITY.md`
- `ARCHITECTURE.md`

`docs/README.md` is the index. The ownership split is:

- What is happening now? → `STATUS.md`
- I have zero context, where do I start? → `CODEX_HANDOFF.md` / `RESUME.md`
- Why is it designed this way? → `ARCHITECTURE.md` + ADRs
- How do I build locally? → `LOCAL_BUILD.md`
- How do I prove it works? → `TESTING.md` + issue #11
- What must match desktop Anki? → `ANKI_DESKTOP_PARITY.md`
- How do maintainers operate/release? → `HANDOFF.md`

Commit `98c5a427172e9add647158039aa6e259ff01dcb9` converted the detailed
build, diagnostics, parity, evidence, PW6 and release sections in `RESUME.md`
into routes to these owners. Its zero-context invariants, source map and entry
commands remain. Continue deduplicating one topic at a time; confirm the owner
contains every fact before removing a repeated paragraph.

### 4.5 Production path vs scaffolding

The five-crate audit is recorded in `crates/README.md`. Four crates are retained
as host-test oracles: `kanki-domain`, `kanki-renderer`, `kanki-platform` and
`kanki-app`. The unreferenced, incomplete `kanki-backend` Rust loader was the
only **obsolete-scaffold** and was removed with before/after host gates. The
production backend remains pinned Anki plus `bridge/`; the production Kindle
application remains the source-owned native code in `device/`.

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

The post-cleanup top-level audit at exact SHA
`55d0a2bf8ed39ef5762cbe94d59d3c4ac51dfb8f` found that the existing directory
split already has one documented owner per responsibility and no tracked
archive/staging/parallel-product root. No directory move was performed. Treat
the tree above as a design vocabulary, not a pending rename checklist; require
a concrete ownership or build-boundary defect before proposing a future
`git mv`.

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

The host gates install no global packages. `tools/install_host_node.sh`
checksum-verifies Node 20.18.2 below ignored `out/`, and
`tools/install_host_jsdom.sh` consumes the source-controlled npm lockfile. The
typed-Anki recipe also imports the seven unmodified public APKGs present in the
pinned Anki submodule and feeds their production packets through one persistent
reviewer `#qa`; see `docs/STATUS.md` for the exact passing SHA and limitations.

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

Then authenticate and execute that exact package against the fixed official
PW6 5.19.6 userspace:

```sh
bash tools/local_pw6_rootfs_audit.sh
```

This last command is a read-only Docker/QEMU loader audit, not PW6 hardware
acceptance. See `docs/LOCAL_BUILD.md` for cache/evidence details and
`docs/STATUS.md` for the exact current result.

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
- ARMHF Anki library plus fixed PW6 rootfs ABI/loader audit; real device
  execution remains separate;
- native GTK2/WebKit app launch on PW6;
- Lab126 CSS pixel/full-content zoom on the actual device;
- old-WebKit generic CSS compatibility corpus;
- scripts/images/SVG/audio/cloze/long-card/cardN behavior and MathJax geometry
  on actual Kindle WebKit (the generic host MathJax lifecycle contract passes);
- the fixed upstream Anki APKG structural path passes; original COCA and other
  rich representative/user APKGs still require unmodified local/device evidence;
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
