# Kindle Anki Port — VM Build Runbook

Updated: 2026-08-22

This runbook is the canonical procedure for continuing the port without GitHub Actions runtime or continuous user supervision. Read `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md` first.

## Policy

- Ordinary build dependencies may be installed in the Linux VM/container.
- The user's Mac is not a compiler requirement.
- Every material source/build/test checkpoint must be committed to the `kindle-anki-port` branch or attached to a GitHub release before being considered durable.
- A local ZIP alone is not a release.
- PW6 hardware acceptance remains a separate gate.

## Continuation order

1. Restore the newest source/worktree checkpoint.
2. Verify the official Anki pin `e5a6fbe27fdd4d57d5f712191b4a753032e57853`.
3. Install/verify build tools: Rust 1.92.0, C/C++ toolchain, protobuf compiler, Node, Python, CMake/Ninja, QEMU user mode, binutils, `file`, `patchelf`, and KindleHF koxtoolchain 2025.05.
4. Initialize Anki Fluent translation submodules.
5. Run strict host C/JavaScript/Shell gates.
6. Repair the Anki backend semantic bridge without exposing generated service internals broadly.
7. Run `cargo check`, semantic tests, and host release build.
8. Cross-build ARMv7 hard-float artifacts.
9. Run ELF/ABI/GLIBC/export/RPATH audits and QEMU/sysroot smoke tests.
10. Assemble and unpack-audit `Kindle-Anki-Port-PW6-armhf.zip`.
11. Persist full ordinary source, logs, manifest, SHA-256, test report, and installer on GitHub.
12. Update `HANDOFF.md` and `PROGRESS.md` after every failed or green gate.

## VM checkpoint convention

A continuation run should preserve:

```text
CONTINUATION_STATUS.md
logs/
ENVIRONMENT_REPORT.md
*.status
Kindle-Anki-Port-VM-continuation.zip
Kindle-Anki-Port-VM-continuation.zip.sha256
```

The status report must include exact commands, exit codes, first root-cause errors, source commit/pin, and the next repair step. Full logs are retained separately; do not paste only the final Cargo summary.

## Current immediate gate

The semantic adapter must compile against the pinned Anki backend. The known design issue is that a crate-root adapter attempted to call private generated `Backend*Service` methods. The repair should use a narrow backend-owned bridge and/or stable `Collection` methods through `Backend::with_col`, while preserving a named semantic C ABI. Do not make all generated service methods public and do not reimplement scheduler or renderer behavior locally.

## Completion rule

Software delivery is complete only when all non-hardware gates are green and the installer, checksum, manifest, test report, source commit, and build provenance are persisted in GitHub. Physical PW6 acceptance is recorded separately and cannot be inferred from VM results.
