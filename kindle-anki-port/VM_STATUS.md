# Kindle Anki Port — VM Continuation Status

Updated: 2026-08-22

## Active execution

VM-side continuation has resumed with permission to install ordinary build/test dependencies. GitHub Actions quota exhaustion is not treated as a compiler blocker.

A continuation driver has been started to:

1. restore the newest source/worktree checkpoint;
2. locate the pinned official Anki source tree;
3. install/verify C, Rust, protobuf, Node, Python, QEMU, binutils and packaging tools;
4. run strict native/web/script syntax gates;
5. inject the semantic adapter into the pinned Anki source;
6. execute the first `cargo check` gate;
7. preserve complete logs, exit statuses, an environment report, a compact root-cause report and a checksum-verified checkpoint archive.

No build gate is marked green here until its exact exit status and evidence have been reviewed and written into `PROGRESS.md`/`HANDOFF.md`.

## Immediate repair target

The first implementation target remains the semantic backend boundary: replace direct calls from a crate-root adapter into private generated `Backend*Service` methods with a narrow backend-owned bridge and/or stable collection-level operations through `Backend::with_col`. Scheduler, renderer, typed-answer and bury behavior must continue to come from official Anki.

## Persistence

The durable procedure is recorded in `VM_RUNBOOK.md`. Every material source or build checkpoint must be synchronized to the `kindle-anki-port` branch; temporary VM archives are only transfer/checkpoint artifacts, not releases.

## User involvement

No local-host action is requested at this stage. A Codex/local-machine assignment will be added to `CODEX_COORDINATION.md` only when a task genuinely requires network/USB access or physical PW6 interaction.
