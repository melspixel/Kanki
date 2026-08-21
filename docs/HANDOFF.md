# Maintainer handoff

A maintainer must be able to reproduce, diagnose, test and release Kanki without reconstructing chat history or depending on one hosted CI provider.

**Start here when taking over:** `docs/RESUME.md`.

`RESUME.md` is the operational entry point; this document defines the permanent handoff contract.

## Handoff source of truth

The repository, PR #10, issue #11, committed documentation and recorded build/test artifacts are authoritative. Chat logs, local scratch directories and undocumented manually assembled ZIPs are not.

Current implementation line:

- `main` — last hardware-accepted legacy line;
- `rewrite-v1` — active source-owned replacement;
- PR #10 — integration PR, kept Draft until closure;
- issue #11 — evidence-backed closure tracker. In that issue, checkboxes mean **verified with evidence**, not merely "code exists".

Before taking over, read in order:

1. `docs/RESUME.md`
2. `docs/STATUS.md`
3. `docs/ARCHITECTURE.md`
4. `docs/ANKI_DESKTOP_PARITY.md`
5. `docs/TESTING.md`
6. `docs/LOCAL_BUILD.md`
7. `docs/INSTALL.md`
8. ADRs under `docs/adr/`
9. issue #11 and PR #10 history

## Source-of-truth pins

The gitlinks under `third_party/` are authoritative. The production core is the pinned Anki source; RAnki is reference-only.

Updating Anki requires a dedicated PR that:

1. changes the Anki gitlink;
2. records upstream release notes, schema/proto/API changes and migration risk;
3. recompiles the semantic bridge rather than preserving obsolete numeric dispatch assumptions;
4. runs host, cross, ABI, renderer and device acceptance suites;
5. updates the compatibility matrix and build identity;
6. never changes application behavior through opaque numeric service IDs.

No dependency may be silently changed from `latest` behavior into a release artifact without recording the resolved source/version in build identity.

## Architectural invariants

The permanent invariants are enumerated in `docs/RESUME.md`. In particular:

- no runtime patching of RAnki;
- no `LD_PRELOAD` backend redirect;
- no hard-coded Kindle logical viewport/media-query rewrite;
- persistent single-WebView `#qa` reviewer lifecycle;
- typed semantic Anki bridge;
- deck-agnostic renderer compatibility only;
- explicit collection ownership across review/sync;
- one manifest-owned PW6 `flock` inode whose descriptor is inherited only by
  the active reviewer/sync collection worker; PID/path checks are not locks;
- `anki_data` is never part of install/upgrade/rollback mutation;
- release components must refuse mixed build identities;
- launch, standalone sync and diagnostic reports share the packaged read-only
  install verifier; manifest-external package files and symlinks are rejected,
  while the documented bounded runtime-state allowlist remains valid;
- verifier preflight completes before callers open logs, inspect locks or copy
  report inputs. Until trust is established, failures go only to stderr; the
  verifier rejects links before reading identity/manifest-owned paths.

Architecture changes require an ADR before or with the implementation change.

## Build identity

Every installable package must contain and expose:

- semantic version;
- Kanki git commit;
- Anki git commit;
- Kindle SDK/toolchain reference commit;
- native audio helper/reference commit where applicable;
- packaged renderer dependency versions/checksums, including MathJax;
- source commit epoch used for deterministic archive metadata;
- target architecture;
- minimum required GLIBC/GCC symbol versions;
- reviewer protocol version;
- SHA-256 manifest of packaged files;
- release gate status.

The launcher must log these values before opening the collection and must refuse to run when component build IDs disagree.

## Canonical build ownership

The canonical package recipe is **not GitHub Actions YAML**. It is:

```text
tools/build_kindle_package.sh
```

Both hosted CI and local builds must invoke that exact script. This removes GitHub-hosted runners as a single point of failure and prevents a hidden second build recipe from drifting.

Executors:

- `.github/workflows/package.yml` — hosted Ubuntu executor and artifact uploader;
- `tools/local_package_docker.sh` — local macOS/Linux executor using `tools/local-builder.Dockerfile`;
- direct Ubuntu 24.04 x86-64 — may invoke `bash tools/build_kindle_package.sh` when its prerequisites match `docs/LOCAL_BUILD.md`.

A local package built from a **clean checkout**, with the pinned builder/toolchain, full manifest/ABI/GLIBC gates and recorded SHA-256 is valid build evidence. It is not automatically hardware acceptance. If hosted Actions are unavailable, release engineering may proceed with the local canonical builder rather than waiting indefinitely for GitHub, provided all remaining issue #11 gates are satisfied and the artifact identity/evidence are recorded.

A manually assembled ZIP that bypasses `tools/build_kindle_package.sh` is never release evidence.

The canonical recipe emits `archive-info.txt`, sorts regular-file paths, fixes
package permissions and derives ZIP timestamps from the source commit epoch.
`tools/create_reproducible_zip.py` is an internal helper of that recipe, not a
second package recipe. Release evidence compares two clean full builds of the
same candidate byte-for-byte using distinct empty Cargo target volumes;
matching manifests or two runs reusing one generated `anki_i18n` cache are
insufficient. The recipe authenticates the fixed Anki i18n build generator,
uses only ordered build-time maps, records the normalization hashes, and
restores the submodule before exit. See ADR 0004.

Host reviewer tests use a project-local, reproducible JavaScript toolchain:
`tools/install_host_node.sh` checksum-verifies Node 20.18.2 for the supported
Linux/macOS host architectures, and `tools/install_host_jsdom.sh` installs
jsdom 24.1.3 from `tools/host-node/package-lock.json`. Both destinations must
remain below ignored `out/`; never require a global Node/npm install and never
copy this host-test runtime into the Kindle package.

Typed Anki native-host integration has a separate canonical test recipe:

```text
tools/run_anki_bridge_host.sh
```

The `typed-anki-host` job in `.github/workflows/ci.yml` and
`tools/local_anki_bridge_docker.sh` are executors for that recipe. Its
disposable collection is always created under `mktemp`; it must never point at
`/mnt/us/anki_data`. The recipe also starts the pinned Anki sync server on a
Docker-local loopback port with scratch state and synthetic credentials, runs
two disposable clients through full upload/download, normal state propagation
and media propagation/status, and scans retained evidence for the synthetic
secrets. Passing establishes controlled review/sync lifecycle behavior and all
24 declared review/sync ABI exports. The same recipe checksum-verifies the
seven public APKGs in pinned Anki, imports each into a separate disposable
collection, renders production packets, and passes their question/answer sides
through one persistent reviewer `#qa`. This is fixed upstream-fixture evidence,
not original COCA/user-deck, live AnkiWeb or PW6 parity.

Both direct and Docker package paths reject a dirty checkout by default. For a
diagnostic build only, `KANKI_ALLOW_DIRTY=1` may be supplied to either
`bash tools/build_kindle_package.sh` or
`bash tools/local_package_docker.sh`; such an artifact is never release
evidence.

Firmware/runtime compatibility has a separate canonical read-only audit:

```text
tools/audit_pw6_rootfs.sh
```

`tools/local_pw6_rootfs_audit.sh` is its Docker executor. Run it only after the
canonical package exists for the clean current `HEAD`. It authenticates the
fixed official PW6 5.19.6 firmware, rootfs and TTS squashfs, checks ARMHF
attributes/symbol versions/dependency closures, and executes loader-level
UI/backend/audio probes plus the complete packaged install verifier through the
PW6 BusyBox shell. It executes the shared operation-lock helper with the
firmware's actual `/usr/bin/flock`, including inherited-worker lifetime, and
also runs the actual packaged redacted-report script with
synthetic private sentinels and rejects non-private, incomplete or leaking
output. Its firmware cache and evidence remain below ignored `out/`; no
firmware bytes enter the package. Passing is Gate D evidence and must retain
`hardware_execution=not_run` until the exact ZIP runs on PW6.

## Build and CI ownership map

- `.github/workflows/actions-probe.yml` — hosted runner/account execution probe only
- `.github/workflows/ci.yml` — invokes the canonical host gate and typed-Anki
  Docker executor; it contains no product build/test recipe
- `.github/workflows/package.yml` — invokes the canonical ARMHF package script
  and uploads the SHA-named ZIP plus build/manifest/archive evidence
- `tools/run_host_gates.sh` — local host gate entry point
- `tools/run_anki_bridge_host.sh` — canonical native-host typed Anki/disposable collection recipe
- `tools/install_host_node.sh` / `tools/install_host_jsdom.sh` — pinned host-test runtime installers below `out/`
- `tools/local_anki_bridge_docker.sh` — local Docker executor for the typed Anki host recipe
- `tools/build_kindle_package.sh` — canonical ARMHF package/ABI recipe
- `tools/local_package_docker.sh` — local Docker wrapper for macOS/Linux
- `tools/audit_pw6_rootfs.sh` — canonical fixed-firmware PW6 rootfs ABI audit
- `tools/local_pw6_rootfs_audit.sh` — local Docker executor for the rootfs audit

The former component ARM bridge, device, audio, CSS and standalone Anki
workflows were removed after the same-SHA local host/Anki/package/rootfs matrix
passed. Their direct compiler/test bodies duplicated the scripts above.
`tools/check_policy.py` now rejects extra workflow sprawl and direct
`cargo`/cross-GCC/npm/test commands in YAML. If a workflow and a canonical
script disagree, reduce the workflow to invoking the script.

## Local build evidence

When GitHub Actions is unavailable or untrusted, record at minimum:

- exact Kanki commit SHA and confirmation that the root checkout was clean before build;
- host OS/architecture and Docker/VM engine version;
- builder platform (`linux/amd64` by default on Apple Silicon);
- Rust version (`1.92.0` for this line);
- `toolchain-info.txt` including koxtoolchain version/checksum;
- `anki-i18n-info.txt` including authenticated upstream/normalized hashes;
- `mathjax-info.txt` and `archive-info.txt`;
- generated ZIP SHA-256;
- `package-exports.txt` and GLIBC evidence;
- package manifest verification result;
- any warnings or emulation limitations.

Perform two clean builds with distinct empty Cargo target volumes before
declaring a release candidate. Compare backend, `BUILD.json`, manifest,
archive evidence and ZIP byte-for-byte. Bit-for-bit reproducibility is a
separate property to verify, not something to assume.

## Diagnostic bundle

A single command must create a redacted ZIP containing enough information to diagnose a device without another custom build:

- build identity and manifest status;
- firmware/system fingerprint without serial/account/Wi-Fi identifiers;
- application and component startup logs;
- Lab126/WebKit capability and pixel-density report;
- bounded reviewer/render metrics;
- privacy-safe renderer structure data by default;
- audio pipeline capability/result data;
- sync state/error category without credentials.

Raw card HTML/CSS capture is explicit opt-in, bounded, and never automatically included in the standard report.

Report creation must use private 0700 directory/work-tree modes and a 0600
archive. A unique partial archive is published atomically only after success;
failure and signal paths remove owned staging without following symbolic output
roots.

The default bundle must not contain:

- AnkiWeb auth tokens;
- account identifiers;
- the collection database;
- unbounded user note content;
- Wi-Fi credentials or device serial identifiers.

Diagnostic directory/bundle creation failure is an explicit error. It must never be swallowed with `|| true` and then reported as enabled.
An install-integrity preflight failure is likewise fatal: do not build a
diagnostic bundle by following log/metrics paths from an unverified tree.

## Test evidence and closure

`docs/TESTING.md` defines the gates. Issue #11 records closure. A checkbox may only close with evidence from the same candidate commit or with an explicit reason why a commit-independent hardware fact applies.

Evidence records should include:

- Kanki commit SHA;
- executor/test identifier (GitHub run, local canonical build, or hardware test);
- architecture/device firmware;
- exact test/fixture;
- artifact/log location;
- result and remaining limitation.

A green build is not hardware acceptance. A device screenshot is not backend/sync acceptance. Old green runs cannot be inherited across behavior-changing commits.

## Branch/release policy

- `main`: last hardware-accepted release.
- `rewrite-v1`: active replacement until issue #11 closes.
- feature branches: focused changes with matching tests/ADR updates.
- tags: accepted source points only.
- generated ZIPs: only the canonical package script may create release candidates; the executor may be hosted CI or the documented local builder.

PR #10 stays Draft until host, Anki bridge, ARMHF, renderer/package and PW6 acceptance evidence all belong to the release candidate.

Historical branch retirement is a provenance-sensitive operation:

1. commit a branch-name to exact-tip-SHA ledger before deletion;
2. audit every unique commit/tree and integrate or explicitly reject its
   behavior on `rewrite-v1`;
3. close superseded PRs without merging rejected experimental architecture;
4. immediately before deletion, read the remote tips again and delete the
   reviewed set atomically with an exact-SHA force-with-lease for every ref;
5. exclude any ref that moved, preserve its live name, and repeat the content
   audit only after the writer and tip have stabilized.

Never include `main` or `rewrite-v1` in a historical deletion set.

## Session-end protocol

Before handing the project to another maintainer or ending a substantial implementation session:

1. update `docs/STATUS.md` with implemented/verified/failing/next state;
2. update issue #11 with new evidence or reopened gates;
3. update `docs/RESUME.md` if the current blocker or next action changed;
4. update `docs/LOCAL_BUILD.md` if local build prerequisites/commands changed;
5. add/update an ADR for architecture changes;
6. ensure the active branch has no important uncommitted-only instructions;
7. link the exact failing workflow/run or local command/output rather than saying only "CI is red";
8. do not claim an installable package is accepted unless its manifest/ABI gates and target hardware gates succeeded.

## Definition of handoff-ready

The project is continuously handoff-ready when all of the following are true, even before release:

- `RESUME.md` tells a new maintainer what to do first;
- `STATUS.md` matches the current branch rather than the first bootstrap commit;
- no critical knowledge exists only in chat;
- dependencies and source pins are visible;
- build/test commands live in repository scripts/workflows/docs;
- the project can be built without depending on GitHub-hosted runners;
- architecture decisions and forbidden shortcuts are recorded;
- active blockers are explicit;
- device rollback and data boundaries are documented;
- test corpus and expected behavior are committed;
- known limitations are listed, not hidden in logs.

Release-ready additionally requires issue #11 completion on the target PW6 against the exact candidate artifact.
