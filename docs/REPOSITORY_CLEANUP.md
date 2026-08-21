# Repository cleanup plan

This document governs repository organization work on the isolated cleanup branch.

## Isolation rule

Repository cleanup must **not** modify `main` directly. `main` is being changed by another workstream and remains the legacy/stable integration line. Cleanup work happens on `handoff-codex-cleanup` and is reviewed through PR #16 into `rewrite-v1` only.

Do not retarget PR #16 to `main`. Do not merge or cherry-pick cleanup commits into `main` from this workstream.

## Current branch inventory

Branches visible at the start of cleanup:

- `main`
- `rewrite-v1`
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

Completed in PR #16 so far:

- removed `tools/patch_sync_ui.py`; its sync-page/state/dispatch changes already exist in `device/kanki_device.c` and the script has no repository references;
- removed `tools/patch_type_answer_ui.py`; its typed-answer device/reviewer/test changes already exist in canonical source and the script has no repository references.

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

PR #16 remains Draft until local baseline evidence is available.
