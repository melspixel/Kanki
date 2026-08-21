# Kindle Anki Port — VM Build Runbook

Updated: 2026-08-22

This runbook is the canonical procedure for continuing the port without GitHub Actions runtime or continuous user supervision. Read `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md` first.

## Policy

- Ordinary build dependencies may be installed in the Linux VM/container.
- The user's Mac is not a compiler requirement.
- Every material source/build/test checkpoint must be committed to the `kindle-anki-port` branch or attached to a durable GitHub artifact before being considered durable.
- A local ZIP alone is not a release.
- Final packaging is forbidden before exact-rootfs QEMU has passed for the exact ARMHF bytes being archived.
- Exact-rootfs L2 requires both the verified extracted PW6 rootfs and the retained rootfs image whose SHA-256 matches the canonical manifest; selected runtime-file hashes alone are not a full-filesystem identity.
- PW6 hardware acceptance remains a separate gate.

## Continuation order

1. Materialize the newest clean `kindle-anki-port` branch head and record its full commit SHA.
2. Verify the official Anki pin `e5a6fbe27fdd4d57d5f712191b4a753032e57853` and use an Anki checkout whose `HEAD` is exactly that commit.
3. Install/verify build tools: Rust 1.92.0, C/C++ toolchain, protobuf compiler, Node, Python, CMake/Ninja, QEMU user mode, binutils, `file`, `patchelf`, and KindleHF koxtoolchain 2025.05.
4. Initialize the required Anki Fluent translation submodules and prepare the offline Cargo cache.
5. Run `testenv/scripts/run-static-gates.sh` from the clean project head.
6. Run the full official host-backend gate and five representative real-APKG C-ABI integrations, including the typed-answer fixture.
7. Run `testenv/scripts/run-armhf-gates.sh` from the same project/Anki identity and preserve `ARMHF-GATES.txt`, `BUILD-PROVENANCE.txt`, ELF/ABI/GLIBC/export reports and the four ARMHF binaries.
8. If either the checksum-matching private PW6 5.19.6 extracted rootfs or its retained `pw6-rootfs.img` is unavailable, stop at an ARMHF checkpoint. Do **not** create `Kindle-Anki-Port-PW6-armhf.zip`.
9. With both private inputs available, run `testenv/scripts/verify-pw6-rootfs.py <rootfs> --rootfs-image <pw6-rootfs.img>` and then `testenv/scripts/run-qemu-smoke.sh` with `ROOTFS=<rootfs>` and `ROOTFS_IMAGE=<pw6-rootfs.img>` against the fresh ARMHF outputs. Preserve `QEMU-SMOKE.txt`, `QEMU-PROVENANCE.txt`, rootfs verification, backend smoke, audio self-test and sync self-test logs. `QEMU-PROVENANCE.txt` must record the canonical rootfs-image SHA-256 without exposing the private path.
10. Only after step 9 passes, run `testenv/scripts/package-and-audit.sh` with `QEMU=<fresh run-qemu-smoke output>`. The package gate independently rechecks source/Anki identity, canonical manifest hash, canonical rootfs-image hash and all four tested ARMHF binary hashes.
11. Re-run package reproducibility/privacy/content audits and persist `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, package contents, ARMHF/QEMU/package provenance and complete test reports durably on GitHub.
12. Update `HANDOFF.md` and `PROGRESS.md` after every failed or green material gate.
13. Begin PW6 hardware-in-the-loop acceptance only after the final non-hardware artifact hashes are recorded. Hardware PASS must be recorded separately.

## Recommended driver

`testenv/scripts/vm-advance.py` encodes the same ordering. Its current contract is:

- static -> official host backend -> real APKG -> ARMHF;
- without `--rootfs`, terminate as `armhf-checkpoint-passed` and do not package;
- `--rootfs` requires `--rootfs-image`; the driver records the image SHA-256 rather than the private path;
- with both private inputs, run exact-rootfs QEMU before package construction;
- pass the resulting QEMU evidence directory into `package-and-audit.sh`;
- never mark physical hardware acceptance.

A package produced by bypassing this order is not valid release evidence even if its ZIP integrity checks pass.

## VM checkpoint convention

A continuation run should preserve at minimum:

```text
report.json
logs/
static-gates/
armhf/
qemu-host-sanity/
qemu-exact-rootfs/          # only when both private rootfs inputs were available
release/                    # only after exact-rootfs QEMU passed
```

The report must include exact commands, exit codes, source commit/pin, relevant tool versions, hashes of logs/artifacts, first root-cause errors, and the next repair step. Do not replace full logs with only a final Cargo summary. Private firmware/rootfs paths must not be persisted in GitHub-facing provenance; use stable hashes/identifiers.

## Current immediate gates

The semantic bridge visibility blocker is already resolved; do not reopen it unless a fresh pinned-Anki build demonstrates a regression.

The current release-critical sequence is:

```text
latest clean canonical head
  -> complete static gates
  -> official Anki 26.08.1 backend + five real APKGs
  -> ARMHF + ABI/GLIBC
  -> checksum-matching PW6 5.19.6 retained-image + extracted-rootfs QEMU
  -> QEMU-bound package-and-audit
  -> durable GitHub installer/reports
```

The current execution container has previously failed ordinary GitHub clone/fetch because external DNS was unavailable, and it does not contain the private checksum-matching PW6 rootfs tree/image pair. Those limitations justify a targeted checkpoint, not a fabricated green full build.

## Completion rule

Software delivery is complete only when all non-hardware gates above are green from one coherent release provenance chain and the installer, checksum, manifest, contents, test report, source commit, ARMHF provenance, canonical rootfs-image hash, QEMU provenance and package provenance are persisted durably in GitHub. Physical PW6 acceptance is recorded separately and cannot be inferred from VM, CI, QEMU or mocks.
