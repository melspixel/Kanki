# Kindle Anki Port — build-entrypoint and sysroot hardening, 2026-08-22

## Scope

This checkpoint continued from branch head `a9356e8995140cde0ae7542a10c9d05f1bf2fe97` and audited newly added VM/test-environment entry points before accepting them as release infrastructure. The branch was also advancing concurrently with deterministic audio-test work; the fixes below were applied by fast-forwarding the same `kindle-anki-port` branch rather than creating an alternate build path.

No final release is claimed in this report. The current execution container could not resolve public Git/HTTP hosts for a normal Anki/toolchain checkout, so the complete canonical-head host/Rust/ARMHF build was not runnable here. Ordinary compilation remains VM-owned and is not delegated to the user's local host.

## Defects found

### 1. Non-executable scripts were invoked directly

The new `testenv/Makefile` and the existing top-level `Makefile`/CI path contained direct execution of scripts stored with Git mode `100644`, including `run-qemu-host-sanity.sh` and test wrappers. Those targets would fail with `Permission denied` even though their shell content was valid.

The canonical entry points now invoke shell scripts through `sh` or `bash` where executable mode is not part of the contract.

### 2. `testenv/Makefile` did not map canonical ARMHF inputs

The new compatibility Makefile supplied `PROJECT_ROOT`/`ANKI_ROOT` to `run-armhf-gates.sh`, while the maintained ARMHF gate requires `PROJECT`, `ANKI`, `CARGO_HOME`, `PROTOC`, and `TOOLCHAIN_BIN`. The compatibility target therefore could not launch the real cross-build.

`testenv/Makefile` now delegates to the top-level canonical Makefile and maps those inputs explicitly.

### 3. New host wrapper silently weakened the official-Anki gate

The initial `testenv/scripts/run-host-gates.sh` only ran `kap_port::tests`, instead of the full official library test command already enforced by `run-host-backend-gates.sh`:

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
```

The compatibility wrapper now runs `run-static-gates.sh` and then `run-host-backend-gates.sh`; it no longer owns a second, weaker Cargo sequence.

### 4. New package auditor bypassed fail-closed package policy

The initial `testenv/scripts/package_audit.py` duplicated an older subset of package checks. It omitted current transient/user-state exclusions such as `*.anki2`, `collection.media/**`, `.sync-request`, `.opened-build`, `.kap-operation.lock/**`, and `.kap-operation.lock.pid.*`.

The compatibility auditor now delegates to both canonical gates:

```text
tools/audit_package.py
tests/test_package_policy.py
```

Synthetic targeted checks confirmed that the canonical policy accepts a valid minimal package and rejects pre-sync Anki backups, collection media, operation-lock state, and sync-request state.

### 5. External sysroot tree hash was path-dependent

`prepare-sysroot.sh` originally hashed the textual output of `sha256sum` over absolute file names. Two byte-identical rootfs trees placed at different directories therefore produced different manifest hashes.

Reproduction with identical trees:

```text
old tree A manifest hash: caca5d1059e3aa6422cb560fdab2a18b4f168a81be61ead89ac60560a073de74
old tree B manifest hash: 27760c6d1020ce552e6318f5ed46d411e47dd9f2912949b6d73cc03157a85ad5
```

The helper now computes `kap-rootfs-tree-v1`: a canonical JSON record set over relative paths, file content hashes, modes, symlink targets, directory entries and special-file identity. The digest is independent of extraction location and changes when a covered file or symlink changes. The helper also fails if `/lib/ld-linux-armhf.so.3` is absent and writes provenance only after the expected digest matches.

Targeted regression:

```text
python3 tests/test_prepare_sysroot.py
test_prepare_sysroot: ok
```

Targeted local content SHA-256:

```text
prepare-sysroot.sh       c45d216956e31a5ced91306283b8e16f79f1623dc541cf585eefbbc23519cfce
test_prepare_sysroot.py  3bfccdb300acbb3e5fdf8abb430e2a2319e5905faff6ef338004a2781b677dbf
```

This generic tree digest is separate from the pinned PW6 firmware/rootfs-image hashes in `pw6-5.19.6-rootfs-manifest.json`; it does not replace the exact firmware/rootfs verifier used by `run-qemu-smoke.sh`.

### 6. VM advance driver could report a false broad success

A concurrent `testenv/scripts/vm-advance.py` initially duplicated Cargo commands, ran only `kap_port::tests`, optionally cross-built only `libanki.so`, skipped the canonical static/native/ABI/package/QEMU gates, and then unconditionally wrote:

```text
software-build-gates-passed
```

That was not an acceptable release-state label.

The driver now delegates to the maintained scripts in order:

```text
run-static-gates.sh
run-host-backend-gates.sh
test_core_integration.py             # when real APKG inputs are supplied
run-qemu-host-sanity.sh              # with KindleHF
run-armhf-gates.sh                   # with KindleHF
package-and-audit.sh                 # with ARMHF outputs
run-qemu-smoke.sh                    # only with exact verified rootfs input
```

It requires an explicit prepared `CARGO_HOME` and pinned `protoc`, verifies the supplied Anki checkout against `upstream.lock.json`, records each exact command/return code/log SHA-256 and artifact SHA-256, and keeps `hardware_acceptance` fixed at `not-run`.

It may emit `non-hardware-release-gates-passed` only when the same run has at least five unique real APKG inputs, a typed-answer APKG input, KindleHF ARMHF/package gates, and exact-rootfs QEMU smoke. Host-only and ARMHF/package-only runs are labelled checkpoints with the missing release gates enumerated.

`tests/test_vm_advance_contract.py` prevents reintroduction of direct narrow Cargo bypasses or the old broad-success string.

## Canonical-entrypoint regression

`tests/test_build_entrypoints.py` now locks the delegation graph. It verifies that:

- top-level Make targets use canonical host, ARMHF, QEMU and package scripts;
- `testenv/Makefile` maps Anki/Cargo/protoc/KindleHF inputs instead of inventing a parallel build contract;
- host compatibility entry points do not contain the old `kap_port::tests` filter;
- package compatibility entry points delegate to the fail-closed auditor and policy;
- CI invokes the non-executable QEMU host-sanity script through Bash.

Targeted reconstruction result:

```text
python3 tests/test_build_entrypoints.py
test_build_entrypoints: ok
```

Targeted reconstruction content SHA-256 values:

```text
Makefile                         f61ccb122b576d4748cec9139ece262273b2fcb5c74132e050a5b38083b151f4
testenv/Makefile                 d5dcc716de5ffd56b1d40c1db711a2b29f86b6e6d81216b12bdb81430137ca01
run-host-gates.sh                25559d1ae46dd77594c0dfc505c599cd7af8793ee1b5d8dc07273d7c588ddaa2
package_audit.py                 e90c5b2dce4e8d9d5a572e46b6ffc1199b21cdc5f186e385c287371a3b543d5a
test_build_entrypoints.py        756b65440256d3c22bec54f57640216304b8a8f752754f8b9739d3a5cc1b4552
.github/workflows/kindle-anki-port.yml
d245675d82f61d628c2f16a89693e40fc7aded1e29422080a6432d7d188b0512
```

Dry-run mapping evidence from the reconstructed Makefiles:

```text
host mapping log SHA-256:  9359750d38270f294623005fac14f600669320cc074db0df4e2ccbd6fb6e897d
ARMHF mapping log SHA-256: bbb935c4315fc861caddd1dd21a57d5c684b09354d98eea16c9dc7106abe7fe4
```

## Static-gate expansion

`run-static-gates.sh` now includes:

- `test_build_entrypoints.py`;
- `test_prepare_sysroot.py`;
- `test_vm_advance_contract.py`;
- syntax/bytecode checks for compatibility package/VM drivers and all canonical build/QEMU/package shell entry points;
- the concurrently added deterministic GStreamer audio fixture (`testenv/tests/audio/test-audio.sh`) so `playbin2`/`mixersink` and protocol behavior are no longer an ungated side test.

## Material commits

```text
512ea0f1a3e51876fd96f841be86ec787a64313f  build: wire canonical host ARMHF QEMU and package gates
45c1f58105c7190ad0c8bb26e71cc0c322dd5e2b  testenv: delegate Makefile to canonical gate scripts
7e670ba9f87129277a26506e5aca985b82a8da95  testenv: make host compatibility gate canonical
3a7ddcc2dd2257fbd57bbee98eb5c75070565fbc  testenv: delegate package audit to fail-closed policy
1ab0e8e35bb96eb9e1e94678b750abdcdd8c33b0  test: lock canonical build and package entrypoints
698c51cb2e6182b40a8739eb0289614190b86005  ci: invoke non-executable QEMU sanity via bash
76d0ad63a5b80f70cf068b27afda244d8f224bd5  test: gate canonical build entrypoint contract
e50761c10bad90336232f8cd3957374958be0af6  test: gate deterministic audio protocol fixture
732eeca8b288b78e5c7f246f3d7e9029e0643038  testenv: make external sysroot hash path-independent
c1af2d41b5cc2b33fc98321a3d6cf9e330007deb  test: cover portable sysroot tree verification
7368192b7ad16adb4b725b1a95a085ca4a50f8df  test: gate portable sysroot preparation
83b4d013f101dc47f488b2b8dfdbe25d4fdc04dd  testenv: make VM driver delegate canonical release gates
83d5d92e04d94acce686d236ae62f093ee4c269d  test: forbid VM driver gate bypasses
c02b58fe2ffda763929f964dac719f2b193065ae  test: gate VM driver and canonical script syntax
```

The audio fixture itself arrived concurrently and was preserved/integrated rather than overwritten.

## What was and was not executed here

Executed targeted evidence:

```text
python3 tests/test_build_entrypoints.py        PASS (reconstructed exact changed files)
python3 tests/test_prepare_sysroot.py          PASS
synthetic canonical package accept/reject     PASS
Makefile host/ARMHF variable-mapping dry-run  PASS
```

A direct public Git clone/fetch from this isolated execution container failed at DNS resolution (`Could not resolve host: github.com`). No exact Anki checkout, offline Cargo cache, KindleHF tree, or private PW6 rootfs bytes are mounted in this container. Consequently this report does **not** claim a fresh canonical-head `make static-test`, official rslib build/test, real-APKG run, ARMHF build, package, or exact-rootfs QEMU run.

The previously recorded package remains a stale checkpoint:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Next canonical execution

On a VM that has the pinned official Anki checkout, prepared offline Cargo cache, pinned protoc and KindleHF toolchain, materialize the latest `kindle-anki-port` head and run the maintained gates from that single commit. The durable driver can be used, but only with explicit inputs; otherwise run the underlying scripts directly.

The release sequence remains:

```text
make static-test
run-host-backend-gates.sh
five-real-APKG test_core_integration.py sequence (including typed-answer fixture)
run-qemu-host-sanity.sh
run-armhf-gates.sh
package-and-audit.sh
verify checksum-matching PW6 5.19.6 rootfs
run-qemu-smoke.sh
```

Then regenerate and persist the final `Kindle-Anki-Port-PW6-armhf.zip`, external SHA-256, internal manifest, package contents, exact command/log bundle, ABI/GLIBC reports and source/build provenance. Physical PW6 acceptance remains a separate HIL gate and cannot be inferred from these VM/QEMU results.
