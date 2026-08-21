# Developer/build tooling

This directory is for **developer-side build, verification and repository tooling**. Scripts installed onto the Kindle belong in `scripts/`, not here.

## Canonical entry points

- `build_kindle_package.sh` — canonical ARMHF package build/validation recipe. CI and local Docker must call this rather than copy its logic.
- `local_package_docker.sh` — macOS/other developer wrapper that runs the canonical package build in a Linux/amd64 container.
- `local-builder.Dockerfile` — pinned local Linux build environment.
- `install_kindlehf_toolchain.sh` — checksum-pinned KindleHF toolchain installer.
- `run_host_gates.sh` — canonical host-side formatting/lint/unit/renderer/source-contract gate.
- `check_policy.py` — architectural source-policy enforcement.

## What must not live here

- one-shot source migration scripts after their edits are canonical;
- manual release ZIP assembly commands that differ from `build_kindle_package.sh`;
- device runtime scripts (`scripts/` owns those);
- historical experiments with no active build/test role.

If a new tool changes source files as part of every build, it must be deterministic, tested, documented and called by the canonical build path. Otherwise prefer putting the final generated/source form directly in the repository.
