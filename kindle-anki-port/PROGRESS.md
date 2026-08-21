# Kindle Anki Port — Current Progress

Updated: 2026-08-21 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Product boundary and source map | complete | Independent desktop-Anki reviewer port; official Anki 26.08.1 pinned |
| Architecture | complete enough to implement | Official rslib + semantic C ABI + Kindle native host + persistent ES5 reviewer |
| Source skeleton | substantial, canonical materialization pending | VM checkpoint `f4fafcd95749cb1318ec57fe4f351856fef8fd31`; ordinary GitHub source tree still needs materialization |
| Rust semantic adapter | **host-green** | Backend-owned `services::kap_bridge` resolves prior private-service E0624 blocker |
| Official Anki rslib tests | **green** | `539 passed; 0 failed` with `--features rustls --lib --offline` |
| Real APKG core integration | **green for 5 decks** | question/reveal/rate/close exercised; typed answer observed; AV observed on 3 decks |
| Kindle native host | host/static green, ARMHF green | strict C99/Werror gates pass; ARM EABI5 hard-float binary produced |
| Web reviewer | static contract green, device rendering pending | persistent `#qa`, script reinsertion, typed input, paging and compatibility code pass static contract tests |
| Audio | implementation integrated, device audio pending | GStreamer/mixersink dynamic worker and self-test pass; real Bluetooth/audible route requires PW6 |
| Sync | implementation now present, live-account acceptance pending | `kap-sync` worker plus collection/full/media/abort ABI compile and export; real auth/network flow not yet accepted |
| Static/lifecycle tests | **green** | injector, semantic/source contract, JS syntax/DOM, C strict build, worker self-tests, lifecycle test pass |
| Host release build | **green checkpoint** | release `libanki.so` built and exports named `kap_*` ABI |
| ARMHF cross-build | **green checkpoint** | `kap-app`, `kap-audio`, `kap-sync`, `libanki-kindle.so` are ARMv7 EABI5 hard-float |
| ABI/GLIBC audit | **green against KindleHF sysroot** | workers require GLIBC_2.4; backend max GLIBC_2.18; real PW6 rootfs QEMU gate still pending |
| Package audit | **green VM checkpoint** | audited ZIP SHA-256 `5a73a0d36941c26790b5fa8ed1a5cd9098ad3f1ab3b0222813888199a21442f4` |
| QEMU/rootfs smoke | harness written, execution pending | ARM smoke harness cross-compiles; full verified PW6 rootfs and working `qemu-arm` not yet available in VM |
| GitHub final persistence | incomplete | build report is persisted; ordinary source tree and final binary asset are not yet both canonicalized on GitHub |
| PW6 acceptance | not started | physical e-ink/touch/framework/Bluetooth/suspend/relaunch evidence required |

## Major blocker resolved

The previous 26-error Rust blocker is resolved. The semantic port no longer calls generated private service methods from crate root. `core/src/services_bridge.rs` is injected as a child of Anki's generated `services` module and exposes only the narrow `pub(crate)` operations required by the Kindle ABI.

This approach preserves the upstream privacy boundary and avoids numeric protobuf service/method indices or broad public API changes.

## Verified VM evidence

Detailed commands/evidence are in `docs/VM_BUILD_20260821.md`.

### Full upstream backend tests

```text
cargo test -p anki --features rustls --lib --offline --no-fail-fast
539 passed; 0 failed
```

### Real APKG integration

Five real decks passed the C ABI review lifecycle test:

- `4000 Essential English Words.apkg` — AV observed;
- `Advanced Vocabulary Complete (20 Units).apkg` — typed answer observed;
- `COCA-English.apkg`;
- `新东方 雅思 乱序版.apkg` — AV observed;
- `百词斩考研.apkg` — AV observed.

### ARMHF / GLIBC

```text
kap-app           ARM EABI5 hard-float, GLIBC_2.4
kap-audio         ARM EABI5 hard-float, GLIBC_2.4
kap-sync          ARM EABI5 hard-float, GLIBC_2.4
libanki-kindle.so ARM EABI5 hard-float, max GLIBC_2.18
```

### Audited VM package

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 5a73a0d36941c26790b5fa8ed1a5cd9098ad3f1ab3b0222813888199a21442f4
```

This is a checkpoint artifact, not a final release, because source/binary GitHub persistence and target-runtime acceptance remain open.

## Build strategy after Actions quota exhaustion

- Iterative builds/tests run in the VM/container with the prepared offline Rust/Cargo/protoc/KindleHF inputs.
- Meaningful evidence is written to GitHub immediately.
- GitHub Actions remains a later independent reproducibility rerun, not a prerequisite for development.
- The user's local host is not used for ordinary compilation.

## Current ordered next actions

1. Materialize VM source checkpoint `f4fafcd95749cb1318ec57fe4f351856fef8fd31` into ordinary `kindle-anki-port/` files in the canonical branch.
2. Verify the materialized tree against source manifest/checksum, then remove obsolete `part-*` archive staging files.
3. Persist the audited ARMHF package, SHA-256, package contents and build provenance to GitHub in a durable form.
4. Obtain/extract the checksum-verified PW6 rootfs and execute the QEMU backend/audio/sync smoke gate.
5. Add deterministic sync decision/error fixtures and broader renderer fixture coverage.
6. Re-run host/ARMHF/package gates from the canonical materialized source rather than the VM-only checkpoint.
7. Begin PW6 hardware-in-the-loop acceptance only after the above non-hardware gates are green and persisted.

## Completion definition

Software release completion requires:

- complete maintainable ordinary source files in GitHub;
- green reproducible host and ARMHF builds from that canonical source;
- QEMU/rootfs target-runtime smoke evidence;
- ABI/GLIBC and package-policy audit;
- `Kindle-Anki-Port-PW6-armhf.zip` plus SHA-256, manifest, contents and test report persisted on GitHub;
- no historical patch runtime dependency and no user data or credentials in the package.

PW6 hardware acceptance is a separate final gate and must be recorded from actual device evidence rather than inferred from VM results.
