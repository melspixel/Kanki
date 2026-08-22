# Developer/build tooling

This directory is for **developer-side build, verification and repository tooling**. Scripts installed onto the Kindle belong in `scripts/`, not here.

## Canonical entry points

- `run_host_gates.sh` — canonical host formatting, lint, unit, renderer and
  source-contract gate.
- `run_anki_bridge_host.sh` — canonical pinned-Anki disposable collection,
  APKG and loopback-sync integration recipe.
- `local_anki_bridge_docker.sh` — local Linux executor for that host-Anki
  recipe.
- `build_kindle_package.sh` — the only canonical ARMHF package
  build/validation recipe. CI and local Docker call it instead of copying its
  logic.
- `local_package_docker.sh` — local Linux/amd64 executor for the canonical
  package recipe.
- `audit_pw6_rootfs.sh` — canonical authenticated PW6 5.19.6 rootfs
  ABI/loader audit.
- `local_pw6_rootfs_audit.sh` — local Docker executor for that rootfs audit.
- `local-builder.Dockerfile` / `pw6-rootfs-audit.Dockerfile` — pinned local
  Linux execution environments; dependencies installed here are not host
  global dependencies.
- `install_kindlehf_toolchain.sh`, `install_mathjax.sh`,
  `install_host_node.sh` and `install_host_jsdom.sh` — pinned/checksummed
  toolchain and test-runtime installers.
- `create_reproducible_zip.py` — internal deterministic archive helper called
  only by `build_kindle_package.sh`; it is not a second package recipe.
- `check_policy.py` — architectural and repository source-policy enforcement.

## What must not live here

- one-shot source migration scripts after their edits are canonical;
- manual release ZIP assembly commands that differ from `build_kindle_package.sh`;
- device runtime scripts (`scripts/` owns those);
- historical experiments with no active build/test role.

If a new tool changes source files as part of every build, it must be deterministic, tested, documented and called by the canonical build path. Otherwise prefer putting the final generated/source form directly in the repository.
