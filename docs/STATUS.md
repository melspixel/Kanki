# Rewrite status

**Branch:** `rewrite-v1`  
**Integration:** PR #10, Draft  
**Closure tracker:** issue #11  
**Release state:** implementation in progress; not yet PW6-accepted  
**Target:** PW6 / ARMv7 hard-float  
**Checkpoint:** 2026-08-22
**Current fully recorded non-hardware candidate:** `a04b2af9ef29cb8c3f06a305dcd596ef06319521`

For zero-context takeover, read `docs/RESUME.md` first. For desktop reviewer semantics read `docs/ANKI_DESKTOP_PARITY.md`. For builds outside GitHub Actions read `docs/LOCAL_BUILD.md`.

## What is implemented

The branch contains source-owned implementations for the major runtime paths:

- pinned Anki 26.08.1 production source core;
- RAnki retained only as a reference gitlink;
- semantic typed Anki review/deck/render bridge;
- semantic typed sync bridge;
- deterministic review-domain state machine;
- persistent Anki-style `#qa` reviewer shell with exact `cardN` classes;
- checksum-pinned, source-owned MathJax 2.7.9 SVG runtime loaded once in the
  persistent reviewer and scoped to `#qa` on each side;
- generic deck-agnostic old-WebKit compatibility;
- source-owned GTK2/WebKit Kindle application;
- Lab126/WebKit CSS-pixel/full-content-zoom feature path;
- source-owned sync lifecycle;
- source-owned loopback audio service and pinned `mixersink` player helper;
- typed bridge deck-config autoplay and answer-side question-replay fields, with bounded ordered reviewer/native sequence consumption and host fixtures;
- delegated reviewer and native WebKit navigation guards that preserve the persistent reviewer and block external navigation without logging full URIs;
- source-owned renderer diagnostics daemon on `127.0.0.1:17393`;
- bounded privacy-safe renderer metrics and explicit bounded raw capture opt-in;
- duplicate-instance/reactivation helper;
- build identity, manifest verification, rollback/data boundaries;
- redacted diagnostic report path;
- three thin hosted executor workflows plus canonical host/Anki/ARMHF scripts
  and handoff docs.

Implementation presence is not the same as verification. Issue #11 remains the closure authority.

## New local build path — GitHub Actions is no longer a compilation single point of failure

The canonical ARMHF package recipe is now:

```text
tools/build_kindle_package.sh
```

GitHub Actions and local builds both invoke this script. `.github/workflows/package.yml` no longer embeds a separate compile/package recipe.

Added:

- `tools/build_kindle_package.sh` — canonical pinned build, package, manifest, exported-symbol and GLIBC gates;
- `tools/local-builder.Dockerfile` — Ubuntu 24.04 + Rust 1.92.0 builder;
- `tools/local_package_docker.sh` — one-command local macOS/Linux executor;
- `docs/LOCAL_BUILD.md` — local build/evidence procedure.

On a developer Mac/Linux machine with Docker/OrbStack/Colima:

```sh
git checkout rewrite-v1
git pull --ff-only
git submodule update --init third_party/anki third_party/kindle-sdk third_party/audiobook-koplugin third_party/ranki-reference
bash tools/local_package_docker.sh
```

The wrapper forces `linux/amd64` by default because the pinned KindleHF toolchain is Linux x86-64-hosted. Apple Silicon uses Docker-compatible amd64 emulation. Cargo and KindleHF downloads are cached in named volumes.

Expected successful output:

```text
out/local-kindle/Kanki-rewrite-hw3.zip
out/local-kindle/Kanki-rewrite-hw3.zip.sha256
out/local-kindle/package-contents.txt
out/local-kindle/package-exports.txt
out/local-kindle/package-glibc.txt
out/local-kindle/sysroot-glibc.txt
out/local-kindle/toolchain-info.txt
out/local-kindle/mathjax-info.txt
out/local-kindle/archive-info.txt
```

The canonical script refuses a dirty root checkout by default, validates source pins, restores temporary Anki bridge injection on exit, and records the exact build identity in `BUILD.json`.

### Verified local baseline

The current clean local non-hardware candidate is recorded for exact SHA
`a04b2af9ef29cb8c3f06a305dcd596ef06319521`:

- host: macOS 26.4.1 x86-64 with Docker Desktop engine 29.4.0, using the
  `linux/amd64` builder platform;
- `sh tools/run_host_gates.sh` — **PASS** using project-local Rust 1.92.0,
  checksum-pinned Node 20.18.2 and lockfile-pinned jsdom 24.1.3; fmt, clippy, policy, native/source
  syntax, 10 retained Rust host-oracle tests, doc tests,
  renderer/CSS/diagnostics contracts,
  semantic ordered-audio and external-navigation contracts, and the app
  self-test passed. The real checksum-verified MathJax 2.7.9 distribution
  produced inline and display SVG across two dynamic renders of the same
  persistent `#qa`; ordinary SVG/image attributes, cloze DOM, long bilingual
  content, answer scrolling and stale-render callback isolation passed.
  Generic flex compatibility maps valid non-negative `order` values to the
  old WebKit natural-number ordinal groups, while leaving negative and
  non-integer values free of invalid legacy declarations. The deterministic
  ZIP host contract and install-integrity contract also passed. The latter
  proves a clean package and bounded runtime state pass while stale regular
  files, symlinks, tampering, missing manifest-owned files and a missing
  manifest are rejected with distinct failures. The runtime-preflight contract
  also proves launch, standalone sync and reporting authenticate and execute
  the verifier before log, lock or report-input access, and symlinks are
  rejected before manifest paths are hashed. The report privacy contract proves
  private modes, unique staging, atomic publication, cleanup after failure and
  exclusion of config/raw captures. The pinned-Anki i18n determinism contract
  authenticates the one build-only `HashMap` to `BTreeMap` normalization and
  rejects drift on either side. The collection-operation contract proves
  atomic contention status 74, exact launcher-to-sync descriptor handoff,
  worker-held lifetime after the wrapper descriptor closes, kernel release
  after the last worker exits and owner-scoped diagnostic metadata cleanup;
- `sh tools/local_anki_bridge_docker.sh` — **PASS**; pinned Anki built as a
  native x86-64 typed library; a backend-created disposable nine-card
  collection passed queue counts, question/answer rendering, semantic
  question/answer sound and TTS extraction, `{{FrontSide}}`, basic typed-answer
  input/comparison, Again/Hard/Good/Easy persistence, user bury, close/reopen
  and health checks. Its sixth card was moved into a filtered deck from a
  normal deck whose autoplay and answer-side question replay were disabled;
  both question and prepared-answer packets preserved the two `false` semantic
  values and SQLite confirmed distinct current/original deck IDs. Three further
  cards passed cloze answer extraction/comparison, known-empty-field marker
  removal and unknown-field warning/marker removal through the production C
  ABI without note-type-specific product logic. A separate
  two-client fixture against a pinned-Anki sync server on loopback passed
  authentication with synthetic credentials, full upload, full download,
  normal-sync deck-state propagation, media byte propagation/status and an
  idle abort. Its evidence and server log passed a scan for the synthetic
  username, password and derived hkey. All 24 C ABI exports declared by the
  review and sync headers were present; library SHA-256 was
  `6312283a7354f096b49d1e2e639a8fd29cede4b2b9b413dd0ada26136db55b8c`;
- the same clean typed-Anki run checksum-verified all seven unmodified APKGs
  available in the pinned Anki test corpus, imported each into its own
  backend-created disposable collection, selected a queued deck, rendered a
  production question packet and prepared answer, then inserted all fourteen
  sides into one persistent reviewer `#qa`. Source APKG hashes remained
  unchanged; note-type CSS remained verbatim; `media.apkg` imported `foo.wav`
  and produced one typed question AV tag. Only structural lengths/hashes are
  logged; the fixed public fixture packets are retained under ignored
  `out/host-anki/apkg-packets.json`;
- `bash tools/local_package_docker.sh` — **PASS**; typed Anki and all six
  ARMHF native executables built, renderer/reproducibility policy passed,
  `MANIFEST.sha256` and the packaged authenticated `kanki-verify.sh` verified
  the complete install tree, forbidden archive paths were absent, and all 24
  required review/sync exports were individually present; required
  GLIBC versions were within the pinned sysroot. The package contains the
  checksum-pinned MathJax runtime/license and records its identity;
- two canonical builds used distinct, previously unused Cargo target volumes.
  Their complete package trees and ZIPs were byte-identical, as were
  `libanki-kanki.so`, `BUILD.json`, manifests, archive evidence and authenticated
  Anki-i18n normalization evidence. Both archives contain 1,299 sorted regular
  files and use source date epoch `1787337609`;
- package SHA-256:
  `7bfb11935d68e4846f557c5f1fe1cb0b372ab5f5d73aa7f1d3cef5f03de1fb4d`;
- byte-identical companion hashes are
  `f9eb906595dbd3edb7c63a3bda3a556b83f71c9c74d7c0558571a3257ba69e69`
  for the ARMHF backend,
  `ef46bda08073d8dcc49b6b58334471975200785c1651d779fcd626e6cca27cc6`
  for `BUILD.json`,
  `79827745976007a21f4116c434b7baf7b5ee58fd3f6892051b35a81f16941fbb`
  for the 1,293-entry manifest,
  `2d33a64f9c421a292cbe9cc3ae1f30267147624a97219bbabd4469bc297020f3`
  for `archive-info.txt`, and
  `624e4be4d450a5d5d0bb7d4dc23c358a82f3286eff474d3ca809dedab0b6e92a`
  for `anki-i18n-info.txt`;
- `bash tools/local_pw6_rootfs_audit.sh` — **PASS** against the authenticated
  official PW6 5.19.6 recovery bundle. The audit verified the 412,492,749-byte
  firmware SHA-256
  `72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c`,
  extracted rootfs SHA-256
  `b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa`
  and TTS squashfs SHA-256
  `0724e2fca5d8bba72681cc5a9d593c68a76f3b0b22a367e613dd01ffba22c15b`.
  The actual complete 1,299-file package verifier executed successfully through
  the PW6 ARM BusyBox shell before the ABI probes; its evidence SHA-256 is
  `b7ab259372014ced118e4ec3efa03e3534f847992c660d4439aa1d55ba999e1c`.
  The packaged operation-lock helper also executed with the rootfs's actual
  util-linux `flock` 2.37.4 and BusyBox shell. Contention, inherited launcher
  handoff, worker-held lifetime and automatic release passed; the probe
  evidence SHA-256 is
  `09716ef39546cf4a5055f6b7161b6b121e241330aa16eeb3c25d5af92265e9b1`.
  All seven packaged ELF objects were ARMv7 hard-float; their required
  GLIBC/GCC/LIBATOMIC versions and loader dependency closures resolved in the
  rootfs. Under QEMU/chroot, the real PW6 loader successfully loaded GTK2,
  GObject, WebKitGTK, X11 and the typed Anki backend, resolved all required UI
  symbols plus all four Lab126 CSS-pixel/zoom symbols, and instantiated
  `mixersink` and `ttssrc` after modeling the firmware's `/usr/lib/tts` mount.
  The packaged report script also ran under that target BusyBox against
  synthetic safe log/metric controls and secret/config/raw-capture sentinels.
  It published a 0700 report tree and 0600 archive atomically, retained the
  safe controls, excluded private inputs, leaked no sentinel and left no work
  or partial file. `redacted-report-privacy.txt` SHA-256 is
  `1183345005329dd02eaf436c74b0b4b97384020e0bc8142d2c5ed3e962079a63`.
  Evidence is under ignored
  `out/firmware/pw6-5.19.6/evidence/a04b2af9ef29cb8c3f06a305dcd596ef06319521/`;
  its self-verifying `EVIDENCE.sha256` SHA-256 is
  `548c550afdc845ab5e5bdacb879c77a558f48888cd372b48b2ca7072714dc536`;
- build identity pins Anki
  `e5a6fbe27fdd4d57d5f712191b4a753032e57853`, Kindle SDK
  `b4a6c99d718a7cf74935f36105c62491b4336a61`, audiobook helper
  `62edf76feb1b7f4af2f01754957e8d57eb3e7d67` and KindleHF 2026.08 SHA-256
  `8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0`;
  MathJax 2.7.9 archive SHA-256 is
  `7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786`.

This evidence is non-hardware baseline evidence, not release acceptance. The
rootfs audit proves package/runtime compatibility and dynamic symbol loading;
it does not create a Kindle display/audio device or execute Lab126 services.
It therefore does not prove native audio output on PW6/AirPods, typed-answer
focus/scroll, MathJax geometry/performance, live AnkiWeb/PW6 sync, independent
cross-host reproducibility, or any real-device lifecycle behavior.

### Repository maintenance checkpoint

Repository cleanup culminated in exact rewrite SHA
`7a0d83975d7f8180f22abec8cc7596e03622ce66`. The complete same-SHA matrix
recorded at that time passed: host gates, disposable Anki review/APKG/sync
integration, two byte-identical canonical ARMHF packages and the authenticated
PW6 rootfs audit. The first host invocation after session restoration stopped
before tests because `cargo` was absent from the restored shell PATH; selecting
the already-installed project-local Rust 1.92.0 resolved the environment
precondition. No compiler, test or package failure was introduced by cleanup.

The useful ownership documentation was integrated, obsolete UI migration
scripts and the sole obsolete Rust backend scaffold were removed after
reference/dependency audits, and 15 static historical/temporary remote
branches were deleted atomically with exact-SHA leases. Superseded PRs #8, #9,
#12, #13 and #17 were closed without merge. `main` remains unchanged at
`f9d2c884a3e191f5975d484675a3283d1bbb4c3d` and PR #10 remains Draft.
`kindle-anki-port` advanced repeatedly during deletion (observed through
`3c0f59d6bc159c86d24748f87677499ed9515bb7`), so that branch and PR #14 were
excluded pending stabilization and a fresh audit.

This cleanup SHA was the first fully recorded non-hardware candidate and has
since been superseded by the fully rerun formal candidate at the top of this
document. The first open release-evidence failure remains physical PW6 Gate E
(`hardware_execution=not_run`), and no original COCA/user APKG is locally
available. Before transferring the candidate, the next command is:

```sh
shasum -a 256 out/local-kindle/Kanki-rewrite-hw3.zip
```

### CI orchestration checkpoint

At exact maintenance SHA
`ca345e5f7c6abb126833e55d3eebe52098d64bf4`, the eight hosted workflows were
reduced to `actions-probe.yml`, `ci.yml` and `package.yml`. The host workflow
now calls only the canonical host gate and typed-Anki Docker executor; the
package workflow calls only the canonical package recipe and uploads an
exact-SHA-named artifact with `BUILD.json`, manifest and archive evidence. The
ARM bridge, device, audio, CSS and standalone Anki YAML compiler/test bodies
were removed. Policy rejects their reintroduction or a fourth workflow.

All three YAML files parsed successfully, `sh tools/run_host_gates.sh` passed,
and a clean canonical package validation at this exact SHA passed in the
separate ignored directory `out/workflow-validation-ca345e5/`; its ZIP SHA-256
is `94915f0933d96105a96598446855cb3ec5e1c94836865c36d662797ce49a4c91`.
That workflow-only validation was not promoted over the then-current complete
candidate, and the later candidate at the top of this document has its own
complete same-SHA evidence. No real compiler, test or package failure was
found. Hosted execution is still
unverified because the known runner-allocation failure occurs before steps.

The recorded branch check found that `kindle-anki-port` was still actively
advancing through `d27258cee6bef948809d12ac38c786e05870cd9f` at 00:21 +08:00,
so it and PR #14 remain excluded from retirement. The next independent
repository-cleanup command is:

```sh
git ls-tree --name-only HEAD
```

### Documentation ownership checkpoint

At exact documentation commit
`98c5a427172e9add647158039aa6e259ff01dcb9`, `RESUME.md` was reduced from
273 to 194 lines by replacing duplicated mutable build, diagnostics, parity,
evidence, hardware and release checklists with links to the owners declared in
`docs/README.md`. Its architectural invariants, source map, hosted/local entry
points and session-handoff rules remain. All referenced owner files exist,
`git diff --check` and `tools/check_policy.py` passed, and no product or package
file changed. The first release failure and next candidate command therefore
remain physical PW6 Gate E and the checksum command above.

### Top-level ownership checkpoint

At exact repository SHA
`55d0a2bf8ed39ef5762cbe94d59d3c4ac51dfb8f`, the tracked top-level tree was
audited after the behavior-preserving cleanup. Root-level files are limited to
repository policy/metadata, the Rust workspace manifests and project notices;
implementation and operational content is contained by `.github/`, `assets/`,
`bridge/`, `crates/`, `device/`, `docs/`, `packaging/`, `scripts/`, `tests/`,
`third_party/` and `tools/`. Every responsibility directory has its own
`README.md`, and the root responsibility map agrees with those owners. No
tracked archive parts, restoration scripts, staging tree or second product
root was found.

No directory move is justified by this evidence, so no cosmetic `git mv` was
performed. This audit changed no product, build or package file and found no
compiler, test or package failure. At that checkpoint the fully recorded
candidate remained `7a0d83975d7f8180f22abec8cc7596e03622ce66`; it has since been
superseded by the candidate at the top of this document. Its first open
evidence failure remains physical PW6 Gate E, with original COCA/user-APKG and
independent-host evidence also unavailable. The next repository-maintenance
command was:

```sh
git ls-remote --heads origin kindle-anki-port
```

### Parallel-port re-audit and flex-order checkpoint

The 19 commits added to `kindle-anki-port` after its initially preserved tip
were re-audited through exact remote tip
`d27258cee6bef948809d12ac38c786e05870cd9f`. Its target-sysroot GLIBC check,
offline-protoc accommodation, fixed-rootfs hashes, QEMU gate, ordinary-source
materialization and CI cleanup are already covered by the rewrite's canonical
Docker builder, sysroot-derived symbol-version gate, authenticated firmware /
rootfs / TTS audit, loader probes, ordinary tracked source tree and three thin
workflows. No parallel source, workflow or VM runbook was imported.

The new branch fixture did expose one generic old-WebKit behavior not yet
covered in the rewrite: modern flex `order`. Commit
`d5f70e061b318202d132203f115dabc00d7bc45b` implements the semantically safe
non-negative subset (`order: n` -> `-webkit-box-ordinal-group: n + 1`) and
retains the original declaration. Negative order is deliberately not mapped
to zero or a negative legacy group because the old property accepts natural
numbers; non-integers are also left without a legacy declaration. This is a
generic browser-feature transform, not deck or note-type CSS. The source and
test hashes are respectively
`bb4148a185f38a12a6483fdeb091b07af21f166fae53a4bb90fc3cf310d50f23`
and `27e6cb185d921930a1051308f77ba54621f30ebff5dafdbb4b9b80dcd080bb70`.

At that exact SHA, host gates, typed Anki disposable review/APKG/sync, two
canonical ARMHF package builds and the official PW6 rootfs audit all passed.
The two package runs were byte-identical with the hashes recorded in the main
baseline above; the rootfs evidence explicitly records
`hardware_execution=not_run`. PR #14 was still an open Draft and its branch had
last advanced only 24 minutes before the second stability check at 00:45
+08:00, so it was not deleted or closed in a race with another writer. Recheck
the exact remote tip and ownership before retirement; no unaudited commit
through `d27258c` is required by `rewrite-v1`.

### Install-integrity checkpoint

The first real failure in the clean-install/rollback category was found by a
read-only source/contract audit: the launch and sync scripts used
`sha256sum -c MANIFEST.sha256`, which rejected missing or modified listed files
but silently accepted an extra stale regular file from another package
version. That contradicted the documented mixed-version refusal contract even
though the existing host and package gates were green.

Commit `b2f6a60c1a7d1c7a1137a4851fe17b6d51ed66cc` is the minimum behavioral
fix. It adds one package-owned verifier, authenticates that verifier from its
exact manifest record before execution, compares the complete regular-file set
against the manifest, rejects all symlinks and permits only explicitly bounded
runtime state. Launch, sync and diagnostic reporting use the same verifier;
the canonical package recipe and host policy own its inclusion and call sites.
No installer touches `/mnt/us/anki_data` or `/mnt/us/extensions/ranki`.

On that exact SHA, the new host contract reproduced and rejected stale,
partial, tampered and symlinked installs; the full host and typed-Anki gates
passed; two canonical packages were byte-identical with the hashes above; the
verifier passed against the actual 1,297-file package tree; and the official
PW6 rootfs audit passed. The required BusyBox `sha256sum`/`grep` forms were also
executed through the target ARM shell under QEMU. No compiler, test or package
error followed the fix. The first open failure remains physical PW6 execution
(`hardware_execution=not_run`); historical upgrade and rollback still require
real-device evidence.

### Runtime-preflight checkpoint

The next read-only call-order audit found a distinct real failure after the
mixed-file verifier itself was correct: `kanki-launch.sh` created/inspected the
lock and could append `kanki.log` before verification; standalone sync could
also append the log first; and the diagnostic report copied identity, metrics
and log inputs before recording its late verifier result. A symlink that should
eventually be rejected could therefore be followed before rejection. The new
contract reproduced the first failure as:

```text
runtime preflight contract: FAIL: launch: '\nverify_installation\n' must execute before 'if ! mkdir "$LOCK"'
```

Commit `5a9151c8d8eab1853ef4b4c986bb79cb0455628a` is the minimum runtime fix:
the verifier rejects links before reading identity/manifest-owned paths, and
launch, standalone sync and reporting authenticate and run it on stderr before
touching the log, lock or report inputs. A failed report preflight creates no
bundle from an unverified tree. Commit
`202c020154386c56ef8f0f6dcdf7a888d9681210` adds the corresponding canonical
target gate by executing the actual complete packaged verifier through the
fixed PW6 BusyBox shell before the existing loader probes. This changes no
Anki, renderer, audio or collection semantics and requires no ADR.

On exact candidate `202c020154386c56ef8f0f6dcdf7a888d9681210`, host gates,
typed Anki review/APKG/sync, two byte-identical ARMHF packages, the actual host
package-tree verifier, target BusyBox verifier and full official PW6 rootfs
audit all passed. No compiler, test or package error followed the fix; no
global package was installed. The first open failure remains physical PW6
launch (`hardware_execution=not_run`), followed by real-device clean install,
historical upgrade and rollback evidence.

### Private-report and fresh-target reproducibility checkpoint

A report-path audit then found a separate privacy/reliability failure: the
diagnostic script created predictable staging paths and wrote the final archive
directly, without owning private directory/file modes or guaranteed cleanup of
partial state. Commit `4013f148257ecd86f2635e0bf1cbfead87dc942e`
is the minimum runtime fix: unique process-owned staging, `umask 077`, explicit
0700/0600 modes, signal/exit cleanup and a hidden partial archive renamed into
place only after `tar` succeeds. Commit
`2261278cd11956ea7ca551a8b7d3c19af410d937` adds execution of that exact
packaged report under the fixed PW6 BusyBox, with synthetic privacy sentinels
and safe controls. It does not read or write real `/mnt/us` data.

The first truly independent package rebuild on `2261278` then exposed a
reproducibility failure that two builds sharing one Cargo target had hidden:
the cached-target ZIP was
`a493e1b0903eb4f376fe6ca3a527f82e880efad32b868738aafb47665bda9724`,
while a previously unused target produced
`43a9e1bea3d0fa6370bb2270f8aac1be3b62a08d09ffe01d0945e5f5b347edfd`.
Only `libanki-kanki.so` and its manifest record differed. The first differing
backend bytes were reordered Fluent translation data generated by pinned
Anki's build script, whose filesystem traversal and randomized `HashMap`
iteration were not deterministic across fresh processes.

Commit `6f48df98ae0c33adff3062ec9011faaf6392e6bc` is the minimum build-only fix.
The canonical host and package recipes authenticate the exact pinned
`gather.rs`, temporarily normalize its three translation maps to `BTreeMap`,
record both hashes and restore the submodule on exit. It does not patch or
change Anki runtime scheduling, rendering, sync or collection semantics. ADR
0004 records this boundary. Documentation commit
`3fed2a3419d1f63cba49f1fe4389be19262a1b2e` was the preceding formal
candidate.

The next active-branch audit found the first real collection-ownership failure:
launch and standalone sync only observed a `.kanki.lock` directory, so two
callers could both pass the check before either created metadata; the launcher's
unconditional stale-directory cleanup could also remove a live owner's
metadata. Commit `7f79a79f421a820c5de1c3042c86dfa9518dbaa8` is the minimum
runtime fix. It serializes launch/sync on one manifest-owned inode with the
fixed PW6 util-linux `flock`, hands the open descriptor to the intended worker,
and leaves `.kanki.lock` as owner-scoped diagnostics only. ADR 0005 records the
boundary. Documentation commit
`a04b2af9ef29cb8c3f06a305dcd596ef06319521` is the formal candidate audited
above. On that one SHA, host gates, typed-Anki disposable review/APKG/sync, two
distinct empty-target ARMHF builds, byte-identical package trees/ZIPs and the
official PW6 rootfs/BusyBox verifier, lock and report audits all pass. The first
open failure is physical PW6 launch (`hardware_execution=not_run`); no compiler,
test, package, ABI or rootfs error remains in this category.

### Baseline failure ledger

- Initial audited SHA: `6e8330a4384af20af2c4404a12f8521638265147`.
- Host preflight first stopped at missing `cargo` (exit 69); Docker initially
  stopped at a non-running daemon. Both were environment preconditions, not
  source failures, and were resolved without global installation.
- The first real package compiler failure was `E0463` while compiling
  `serde_repr`, caused by sharing Anki's Cargo target directory through a
  Docker Desktop source bind. Commit `9edcb719b40c3f669415418ffd2cd19a6b14f07e`
  moved only that target cache to a named volume.
- The next compiler category was 31 typed-bridge errors against pinned Anki
  26.08.1. Commit `8f5fa0b2c6316a2f708bdafadec2ca391e17cd38`
  restored the semantic C ABI and pinned service/proto contract while retaining
  effective deck playback fields.
- Subsequent host categories fixed a forbidden global image rule, fail-open
  package assertions and portable diagnostics loopback binding in separate
  commits. The clean baseline above is the first SHA after all of them.
- Commit `512cb803c01cc6a9b2c94c99cd0c7ad908378c3e` fixed the next behavioral
  category: autoplay is now controlled only by the typed backend boolean,
  answer playback conditionally queues question then answer AV tags, and the
  loopback service owns one bounded ordered job. Host and ARMHF package gates
  pass at that exact SHA without changing generic SVG/image behavior.
- Commit `95525f8d195e3587eec666498d6cd6722dae2258` fixed the next behavioral
  category: delegated reviewer links and native WebKit policy now block
  external navigation while preserving same-document navigation and the
  persistent reviewer. The canonical host gate now includes this contract.
- The first disposable review integration run then exposed a product error:
  full rendering expanded raw `{{FrontSide}}` before AV extraction, duplicating
  question AV into the answer and changing its replay side. Commit
  `868b07a15ec09be2790f97e339e4a7984c8a7afb` switched to pinned-Anki partial
  rendering, expands only the semantic `FrontSide` replacement, and preserves
  q/a marker identity. A later `-2` versus `-3` bury mismatch was corrected in
  the test oracle after confirming pinned Anki records user bury as `-3`; no
  product bury behavior was changed for that mismatch.
- Commit `dc53cc89603428b5b41bc9b223dc07a6222c2f65` added pinned-backend
  executable evidence for both playback booleans with default-enabled and
  disabled effective deck values, including filtered-card original-deck
  inheritance. The first diagnostic and clean runs passed without a product
  change; modifying the bridge would have been an unjustified behavioral
  change.
- The controlled sync diagnostic at
  `eed36e5be94d9557d7d70df642a4b778bb83fddf` passed without a product sync
  change. Its audit instead found that the host/package export checks accepted
  any matching semantic symbol rather than requiring the complete ABI. The
  review and sync headers now have one source-controlled 24-symbol requirement
  list consumed by both canonical recipes, and every symbol is checked
  individually.
- The first package-workflow failure in that category was exit 71 before
  compilation: `tools/local_package_docker.sh` did not forward the existing
  `KANKI_ALLOW_DIRTY=1` diagnostic flag into the container. The wrapper now
  forwards that flag while retaining the default value `0`; dirty builds remain
  invalid as release evidence. The subsequent clean host, Anki and ARMHF
  package runs passed at the exact baseline SHA.
- Commit `c2a513f1acdcc1cf778515374e2aef58d9099eb2` added disposable cloze,
  known-empty and unknown-field typed-answer evidence. The pinned-Anki
  diagnostic passed without a product change. A direct host invocation first
  stopped at the already-documented missing-`cargo` PATH precondition (exit
  69); with the project-local toolchain selected, the first real gate failure
  was one rustfmt line wrap in the host-only fixture. Formatting that fixture
  was the complete fix. Clean host, Anki and ARMHF package runs then passed at
  the exact commit.
- Commit `57095b034020ea24c3525878abf307e0d5f0e7bc` closed the next source-owned
  renderer gap: pinned Anki correctly left MathJax delimiters in card HTML, but
  Kanki's reviewer supplied no formula runtime. The fixed upstream MathJax
  2.7.9 SVG distribution is now checksum verified, loaded once, and typesets
  only the persistent `#qa` with render-generation isolation. The first real
  vendor-contract failure was an over-strong oracle expecting optional
  `data-mathml` output from the selected config; actual SVG and semantic TeX
  were correct, so the oracle was narrowed without changing the runtime. The
  next navigation-contract failure showed its host fixture had not loaded the
  new adapter; aligning that host oracle was the complete behavioral fix.
  Clean host, Anki and ARMHF package gates then passed at the exact commit.
- The first repeated canonical builds of `57095b034020ea24c3525878abf307e0d5f0e7bc`
  produced hashes `a15f35eaa027d7ad0c27f492ad7113aeb6361e9c72f2f44fa1f3d5d9b92254a8`
  and `dc316855fcf12d490dc13fa5a18d0787f39708f879f1b5010daf88f9a852184f`.
  Their `BUILD.json` and 1,290-entry content manifests were identical; only ZIP
  build timestamps/order metadata differed. Commit
  `4b11acb9cb2c029c1349093683ee1335a1295149` binds archive time to the source
  commit, sorts paths, fixes file modes/ZIP metadata, records archive identity
  and adds an executable host contract. Two subsequent clean ARMHF builds were
  byte-identical at `f0ba4c91d3f8bf7f5e8eda29f508cbaafa3ec0a995b898e7e256af2b9a114c37`.
- Commit `96b326c0da1fdcbe96f519ac84f3f1f985ec403e` added the first
  unmodified-APKG executable path. The inventory found only seven fixed public
  APKGs in pinned Anki; no COCA or user deck is present, so no substitute was
  fabricated. All seven passed import -> queue -> backend packet -> prepared
  answer -> persistent reviewer without a product-code fix. After environment
  restoration, the first preflight stop was a missing host `rustfmt` PATH;
  the existing project-local Rust toolchain resolved it. Installing Ubuntu's
  global `npm` set in the builder would have added roughly 875 MB/480 packages,
  so that diagnostic build was aborted and replaced with checksum-pinned Node
  plus lockfile-pinned jsdom under ignored `out/`. Clean host, Anki and two
  byte-identical ARMHF package builds then passed at the exact commit.
- Commit `17936f08ab416388314d626478ba52c61eec56a2` added the fixed PW6
  5.19.6 rootfs audit and a device `--abi-probe` that loads the real UI and
  typed backend DSOs but stops before assets, collection access, GTK init or a
  window. The first audit failure was evidence-tooling identity: the full
  firmware target OTA `4832160042` had been confused with the shorter rootfs
  build `483216`. Commit `4afafea506beee50677557560e35f7afefd55981`
  records and validates them separately.
- The next audit failure was Docker Desktop filesystem behavior: hard-linking
  the extracted rootfs from a macOS bind mount into a chroot failed even though
  the rootfs itself was valid. Commit
  `860523091d9d731521b1b05de749a3f0b9028685` stages a normal copy in
  container-local `/tmp`, with narrowly validated cleanup paths.
- The next failure was another audit-oracle defect: a greedy X11 source regex
  crossed line boundaries and treated the `LOAD_FN` macro definition as a
  symbol. Commit `313d52d8aeb7b37b6b421b69609d059b30916ecb` parses one source
  line at a time and requires the exact nine-symbol set. No symbol requirement
  was removed. Host, typed-Anki/APKG/sync, two canonical package builds and the
  full PW6 rootfs audit then passed on that exact SHA; no product ABI failure
  was observed.
- There is no red canonical local software gate at this checkpoint. The next
  missing executable categories are original COCA plus an unrelated rich APKG,
  independent cross-host reproduction and real PW6 hardware acceptance.

## Current GitHub-hosted Actions blocker

Hosted Actions remains broken before job execution.

At PR head `fc4879c609ca95978c3ed202a8c485c6993a1d7c`, minimal **Actions runner probe** run `32475742329`, job `96751577470`, completed `failure` with `steps = null`. All normal workflows on that head failed before useful execution.

This remains an account/repository/runner infrastructure problem class, not evidence of a Kanki compiler failure. Do not change product source merely because those zero-step jobs are red.

Hosted CI can be repaired later and rerun as independent confirmation; it is no longer required to discover real compiler errors because the package can be built locally using the same canonical script.

## Desktop Anki parity state

The direct audit against pinned Anki 26.08.1 corrected and clarified several items:

- typed-answer `{{FrontSide}}` separator placement, cloze extraction/comparison, known-empty fields and unknown-field markers now have executable pinned-backend fixtures; real Kindle focus/scroll remains pending;
- autoplay must be derived from effective deck config (`!disable_autoplay`) rather than AV-tag presence;
- answer-side question replay must honor effective `!skip_question_when_replaying_answer`, including filtered-card original deck behavior;
- the pinned-backend disposable fixture now proves enabled and disabled packet values plus filtered-card original-deck inheritance; native PW6 playback remains open;
- the pinned v3 scheduler uses four rating buttons, so the Kindle four-button bar is not a parity defect for this pin;
- external navigation is blocked by both reviewer JavaScript and native WebKit policy while same-document navigation remains allowed; PW6 policy-callback evidence remains pending;
- upstream MathJax 2.7.9 SVG output is packaged and exercised across dynamic
  persistent-reviewer renders; real Kindle WebKit geometry/performance remains
  pending;
- seven unmodified pinned-Anki APKG fixtures now pass semantic import, queue,
  render/AV packet and persistent-reviewer transitions; this is not evidence
  for COCA, arbitrary user decks or Kindle geometry;
- Lab126 CSS-pixel lifecycle behavior still requires PW6 proof.

See `docs/ANKI_DESKTOP_PARITY.md` for the exact source-level rationale.

## Renderer diagnostics state

Normal launch is designed to create:

```text
/mnt/us/extensions/kanki/render-debug/
/mnt/us/extensions/kanki/render-debug.previous/
```

Default metrics include bounded structural/layout information but no element text. Raw HTML/CSS/AV capture requires:

```text
/mnt/us/extensions/kanki/enable-render-capture
```

Raw capture is bounded and never included automatically in the redacted report. Diagnostic startup failure is a launcher error rather than a silent loss of observability.

## Previously achieved development evidence

Earlier iterations established useful but non-closing evidence for:

- Rust review state-machine behavior;
- persistent reviewer/`#qa` contract;
- card body classes;
- question/answer/rating flow contracts;
- replay SVG isolation from unrelated SVG;
- individual ARMHF native/audio compilations;
- parts of typed Anki integration;
- generic CSS compatibility tests.

Because behavior-changing commits landed afterward, these do not close the current release candidate. Final gates require same-candidate evidence.

## What is still not verified/closed

- end-to-end ordered AV autoplay and answer-side question replay on PW6/AirPods;
- typed-answer focus, keyboard and answer-scroll behavior on PW6 WebKit;
- live AnkiWeb sync and normal/full/media sync acceptance on PW6;
- independent cross-host reproducibility confirmation; two distinct empty
  Cargo targets on this host are byte-identical;
- native GTK/WebKit window behavior and computed CSS-pixel geometry on PW6;
- audio sequence behavior on PW6/AirPods;
- renderer diagnostics daemon behavior on ARMHF/PW6;
- original unmodified COCA plus an unrelated rich/user APKG and their PW6
  geometry; the seven small pinned-Anki APKG fixtures pass on host;
- physical clean install / historical upgrade / rollback; host/package mixed-
  install integrity passes;
- physical-device diagnostic capture/privacy confirmation; the host contract
  and synthetic PW6 BusyBox archive inspection pass;
- PW6 review/sync/scroll/sleep-wake/USB lifecycle acceptance;
- independent maintainer reproduction from repository docs only.

## Immediate next actions

1. Preserve candidate identity before device transfer with
   `shasum -a 256 out/local-kindle/Kanki-rewrite-hw3.zip`; the expected value
   is `7bfb11935d68e4846f557c5f1fe1cb0b372ab5f5d73aa7f1d3cef5f03de1fb4d`.
2. Obtain explicit local test access to original COCA and at least one
   unrelated representative APKG, then run the same privacy-reviewed path
   without modifying or committing the decks and without adding deck CSS.
3. Connect the target PW6, back up user data, follow `docs/INSTALL.md`, and
   clean-install this exact ZIP into `/mnt/us/extensions/kanki` without
   deleting/replacing `/mnt/us/anki_data` or touching
   `/mnt/us/extensions/ranki`.
4. Run Gate E in `docs/TESTING.md`, retaining build identity, firmware,
   renderer geometry, audio, diagnostics/privacy, sync, lifecycle and rollback
   evidence against this exact artifact. The first currently open evidence
   item is physical PW6 launch; `hardware_execution=not_run` is recorded in
   the rootfs audit rather than hidden as a pass.
5. Reproduce the canonical package on an independent host and compare the ZIP
   byte-for-byte.
6. Repair/rerun hosted Actions later as independent confirmation, not as a
   separate build definition.

## Release rule

Do not merge PR #10, close issue #11, tag `1.0`, or call the rewrite finished until the exact candidate artifact has passed the applicable software gates and PW6 hardware acceptance. The candidate may come from hosted CI or the documented local canonical builder; ad-hoc manually assembled ZIPs do not qualify.
