# Repository cleanup plan

This document governs repository organization work on the isolated cleanup branch.

## Isolation rule

Repository cleanup must **not** modify `main` directly. `main` is being changed by another workstream and remains the legacy/stable integration line. Cleanup work happens on `repo-cleanup-v1` and is reviewed into `rewrite-v1` only.

Do not retarget the cleanup PR to `main`. Do not merge or cherry-pick cleanup commits into `main` from this workstream.

## Current branch inventory

Branches visible at the start of cleanup:

- `main`
- `rewrite-v1`
- `repo-cleanup-v1`
- `handoff-codex-cleanup`
- `ci-validation`
- `anki-26.08-backend`
- `desktop-anki-kindle-port`
- `dropin-native-renderer`
- `kanki-next-bootstrap`
- `kindle-anki-port`
- `kindleanki-v1-closure`
- `refactor-anki-compat`
- `renderer-adaptive-v2`
- `test2-ci`
- `test3-native-audio`
- `test4-audio-ui`
- `test4-final`
- `test5-coca-layout`

Most non-`main`/`rewrite-v1` branches are historical experiments. Do not delete branch refs in the first cleanup phase. A local maintainer should first record `branch -> tip SHA`, determine whether any unique source is still required by `rewrite-v1`, and preserve archival tags or another durable map before deleting stale refs.

### Initial branch containment audit

The following comparison uses `rewrite-v1` as the base and asks whether the historical branch has commits not already contained in the rewrite.

| Branch | Ahead of `rewrite-v1` | Initial classification | Action |
|---|---:|---|---|
| `main` | n/a | concurrent/legacy integration line | **Do not touch from cleanup workstream** |
| `rewrite-v1` | n/a | active rewrite | cleanup PR base only |
| `repo-cleanup-v1` | n/a | isolated cleanup | active |
| `ci-validation` | 4 | divergent; changes old build/audio paths and may belong to another workstream | **Do not touch** until owner confirms |
| `desktop-anki-kindle-port` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `kindleanki-v1-closure` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `refactor-anki-compat` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `test3-native-audio` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `test4-audio-ui` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `test4-final` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `test5-coca-layout` | 0 | fully contained in rewrite history | retirement candidate after tip SHA is recorded |
| `test2-ci` | 1 | only unique file is `ci-test2.txt` | retirement candidate; record tip first |
| `anki-26.08-backend` | 10 | unique historical backend-redirect experiment | archive-only; do not merge into rewrite |
| `renderer-adaptive-v2` | 38 | unique historical renderer/firmware-audit patch stack | archive-only; do not merge wholesale |
| `dropin-native-renderer` | 42 | unique historical drop-in renderer/oracle work | archive-only; inspect only for missing evidence/docs |
| `kanki-next-bootstrap` | 42 | previous standalone `projects/kanki-next` experiment | archive-only; do not resurrect parallel product tree |
| `kindle-anki-port` | 14 | previous overlay/source-archive port experiment | archive-only; contains split overlay/source artifacts |
| `handoff-codex-cleanup` | divergent | superseded first cleanup branch | retire after PR #16 is closed and `repo-cleanup-v1` is confirmed |

The important distinction is **contained vs divergent**, not branch age. Contained branches can normally be removed after tip capture. Divergent branches should be preserved as historical tags or a committed branch→SHA map before deletion; they should not be merged wholesale into the source-owned rewrite.

## What is actually one project

The rewrite is a monorepo, not several unrelated applications. Current ownership is:

- `crates/` — Rust domain/host abstractions and self-test model.
- `bridge/` — semantic Anki C ABI injected into the pinned Anki source.
- `device/` — source-owned Kindle-native processes.
- `assets/` — persistent reviewer and device web UI.
- `scripts/` — scripts that execute on the installed Kindle package.
- `tools/` — developer/build/test tooling.
- `packaging/` — install-facing files and Kindle-home shortcuts.
- `tests/` — source/renderer/diagnostic contracts.
- `third_party/` — pinned upstream references/dependencies.
- `docs/` — architecture, current state, build, parity, testing and handoff.
- `.github/workflows/` — CI executors only; build logic belongs in `tools/`.

Do not split these into separate repositories during the rewrite. The ambiguity should be fixed through ownership, naming, removal of obsolete transition artifacts and smaller workflow/document sets.

## Cleanup phases

### Phase 1 — safe deletions and ownership

Behavior-preserving only.

- Remove one-shot migration scripts after proving their result is already canonical source.
- Add/maintain ownership/index documentation.
- Identify generated files and ensure they are ignored rather than committed.
- Classify every top-level directory and every Rust crate as production, test oracle, planned, or obsolete.
- Do not rename production directories yet.

Completed on `repo-cleanup-v1` so far:

- removed `tools/patch_sync_ui.py`; its sync-page/state/dispatch changes already exist in `device/kanki_device.c` and the script has no repository references;
- removed `tools/patch_type_answer_ui.py`; its typed-answer device/reviewer/test changes already exist in canonical source and the script has no repository references;
- added ownership README files for `tools/`, `bridge/`, `device/`, `tests/` and `crates/`;
- performed the first branch containment audit without deleting historical refs.

### Phase 2 — local baseline before structural moves

Run from a clean local checkout:

```sh
sh tools/run_host_gates.sh
bash tools/local_package_docker.sh
```

Record exact SHA, host environment, first failure, toolchain identity and package evidence. Fix only real failures. Do not do a large directory move while the baseline is unknown.

### Phase 3 — reduce workflow/build duplication

Once local build/test entry points are healthy:

- keep `tools/build_kindle_package.sh` as the canonical package recipe;
- make CI call canonical scripts instead of carrying duplicate commands;
- consolidate component workflows only when doing so preserves narrow diagnostics;
- remove `actions-probe.yml` after hosted runner infrastructure is healthy and the probe is no longer useful.

A likely target is:

- `ci.yml` — host/source/unit/renderer contracts;
- `kindle.yml` — ARMHF bridge/device/audio/diagnostics/ABI;
- `package.yml` — package invocation + artifact upload.

### Phase 4 — optional physical layout cleanup

Only after baseline tests are green. Prefer `git mv` in small commits. Potential long-term naming:

```text
integrations/anki/   <- bridge/
platform/kindle/     <- device/
ui/                  <- assets/
runtime/             <- scripts/
build/               <- developer build/toolchain scripts
```

These moves are optional. Do them only if they materially improve ownership and do not create churn in build/package paths.

### Phase 5 — historical branch retirement

After the active rewrite is proven self-contained:

1. record every stale branch tip SHA;
2. inspect/compare unique commits against `rewrite-v1`;
3. preserve archival tags or a committed branch map if historical recovery matters;
4. delete obsolete experimental branch refs;
5. retain only `main`, the active integration branch, and short-lived focused branches.

## Cleanup boundaries

Repository cleanup must not silently change:

- Anki scheduling/rendering/sync semantics;
- persistent reviewer lifecycle;
- Kindle CSS-pixel behavior;
- audio behavior;
- package paths on device;
- collection ownership;
- `/mnt/us/anki_data` safety boundaries;
- deck/card rendering rules.

If cleanup exposes a semantic defect, document it and fix it in a separate focused commit/PR unless the cleanup itself cannot proceed without the fix.

## Acceptance for cleanup PRs

A cleanup commit should have one of these proofs:

- file is unreferenced and its effect is already canonical;
- move/rename is mechanical and all references are updated;
- duplicate build logic is replaced by a canonical script with the same checks;
- documentation ownership is clarified without deleting unique information.

The cleanup PR remains Draft until local baseline evidence is available.
