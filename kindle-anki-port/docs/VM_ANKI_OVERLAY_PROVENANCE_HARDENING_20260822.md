# VM report — deterministic Anki overlay provenance hardening

Date: 2026-08-22 UTC

## Scope

This checkpoint audits the remaining source-provenance boundary between the exact official Anki 26.08.1 checkout and the maintained Kindle semantic bridge. It does **not** claim a complete current-head build, exact-rootfs QEMU run, final package, or PW6 hardware acceptance.

Official Anki pin:

```text
e5a6fbe27fdd4d57d5f712191b4a753032e57853
```

## Defect found

The previous host/ARMHF gates proved that the Anki checkout's `HEAD` resolved to the pinned commit, but they did not fully prove that the **working-tree bytes compiled by Cargo** were exactly that commit plus the maintained Kindle bridge.

Two concrete failure modes followed:

1. `run-host-backend-gates.sh` checked only Anki `HEAD`, then ran the injector. Any unrelated dirty tracked/untracked Anki source already present before injection could survive and participate in the official host build.
2. `run-armhf-gates.sh` checked only Anki `HEAD` and assumed the host-time injection was valid. Because Git `HEAD` does not constrain working-tree modifications, an arbitrary dirty Anki tree could still be compiled while provenance recorded the correct pinned commit.

A secondary reproducibility weakness was that both Cargo invocations could reuse an ignored `target/` directory from an earlier build or a caller-supplied `CARGO_TARGET_DIR`. Cargo normally fingerprints dependencies correctly, but release provenance should not depend on pre-existing ignored build state when a clean rebuild is affordable.

## Production hardening

### `tools/inject_into_anki.py`

The injector now derives the expected overlay bytes from two authenticated inputs:

```text
pinned Anki HEAD blobs
+ clean kindle-anki-port project sources
= deterministic injected Anki working tree
```

For a Git checkout it now:

- resolves `HEAD^{commit}` rather than accepting a merely printable ref;
- reads `rslib/src/lib.rs`, `rslib/src/services.rs`, and `rslib/Cargo.toml` directly from pinned `HEAD`;
- constructs the expected one-time module declarations and `rlib`/`cdylib` crate type from those HEAD blobs;
- requires `rslib/src/kap_port.rs` to byte-match `core/src/port.rs`;
- requires `rslib/src/services/kap_bridge.rs` to byte-match `core/src/services_bridge.rs`;
- requires `.kap-upstream-commit` to contain the exact pinned commit;
- verifies the final bytes of every overlay-owned path;
- computes tracked, staged, submodule-visible and untracked Git changes using NUL-delimited Git plumbing;
- requires the dirty-path set to equal exactly the deterministic overlay delta from pinned HEAD;
- rejects unrelated tracked, staged or untracked source changes.

Non-Git prepared source bundles remain supported only through the existing exact `.kap-upstream-commit` marker path; release host/ARMHF gates themselves still require real resolvable Git checkouts.

### `testenv/scripts/run-host-backend-gates.sh`

After project/Anki identity checks, the host gate now runs the hardened injector and therefore proves that the checkout is exactly pinned Anki + deterministic Kindle overlay before Cargo starts.

It then overrides any caller `CARGO_TARGET_DIR` with:

```text
$ANKI/target
```

and deletes that directory before `cargo check`, `cargo test`, and the release host build. `vm-advance.py` therefore continues to find the resulting host library at the existing canonical path `checkout/target/release/libanki.so`, but stale ignored target bytes cannot be reused across release-gate invocations.

### `testenv/scripts/run-armhf-gates.sh`

The ARMHF gate now independently reruns the idempotent hardened injector before cross-compilation. This removes the previous implicit trust in whatever dirty overlay the host gate happened to leave behind.

It also forces `CARGO_TARGET_DIR=$ANKI/target` and removes it before the ARMHF build, so the cross build starts from fresh Cargo output while preserving the existing output location contract.

## Regression tests

`tests/test_injector.py` now covers a real temporary Git checkout in addition to the historical non-Git source-bundle fixture. It checks:

```text
clean deterministic injection                       PASS
idempotent deterministic reinjection                PASS
unrelated untracked source is rejected              PASS
overlay-owned byte tamper is rejected               PASS
unrelated tracked source is rejected                PASS
unrelated staged source is rejected                 PASS
```

`tests/test_armhf_provenance.py` now also proves that the ARMHF gate calls the injector before Cargo and recreates the gate-owned `$ANKI/target` even when the caller supplies another `CARGO_TARGET_DIR` and a stale `target/release/libanki.so` exists.

Both tests remain part of `run-static-gates.sh`.

## Targeted execution performed in this VM

Normal GitHub networking is still unavailable in the execution container, so the complete repository could not be cloned for a truthful current-head static/backend/ARMHF run. The direct probe remained:

```sh
git ls-remote https://github.com/melspixel/Kanki.git
```

Result:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

I therefore ran a standalone local Git reproducer implementing the new deterministic-overlay predicates and Cargo-target invariant. Exact persisted result:

```text
py_compile: PASS
clean deterministic injection: PASS
idempotent reinjection: PASS
unrelated untracked source rejection: PASS
overlay-owned byte tamper rejection: PASS
unrelated tracked source rejection: PASS
unrelated staged source rejection: PASS
gate-owned Cargo target recreation / caller target isolation: PASS
targeted cases: 7/7 PASS
```

Evidence:

```text
docs/logs/KAP_ANKI_OVERLAY_TARGETED_20260822.log
SHA-256 d3240f300e6b5605ead549f780d93907abfd8b38005d8536ad2d1c3db79040e8
```

This is targeted regression evidence only; it is not a substitute for the full static gate or official Anki build.

## Persisted code/test commits

```text
585523a5eb8a8c91233c85bd6cddd8831db8c27a  harden deterministic Anki overlay provenance
5fbf7d1f5525511eab3aa4b674ea546a7439051c  bind host build to verified Anki overlay
ac4c01fab849d2fbc4d2a4f5e575c4f9f7f9bedc  bind ARMHF build to verified Anki overlay
bfb57dbca01379fd924bbe15588fc0e20d262f13  test ARMHF overlay injection and fresh Cargo target
84381f9cf79ebfc0de7cd537ef4067b4eed257b4  test deterministic Anki overlay provenance
16141e984efcf12144dbe95af3fdbb4e68c55c5c  persist targeted overlay evidence
```

Production/test blobs after these changes:

```text
tools/inject_into_anki.py                     b7cf140e742c219ca0fe7acc675a08fe075e9c17
testenv/scripts/run-host-backend-gates.sh     3e2e463385713d096efab5a1f3c5ba5b065941ec
testenv/scripts/run-armhf-gates.sh            197054ebfd84b6b24d7f5237a79149f4ad7ccacb
tests/test_armhf_provenance.py                bc8fcfddde7657ad2df3646d541a9963ef887707
tests/test_injector.py                        9f8da713f59cf46ecfb42a49402426ff7a1ab858
```

## Release impact

All historical official-Anki/ARMHF evidence remains checkpoint evidence only. The new overlay rule is stricter than the historical provenance model, so the eventual release must rerun host and ARMHF gates from one fresh current source identity.

No old ZIP may be promoted. The stale checkpoint remains:

```text
Kindle-Anki-Port-PW6-armhf.zip
SHA-256 9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225
```

## Ordered next actions

1. Materialize the then-current clean `kindle-anki-port` head in a network-capable VM with complete Git objects and the exact Anki 26.08.1 checkout.
2. Run full `run-static-gates.sh`, including the updated injector and ARMHF provenance tests.
3. Run `run-host-backend-gates.sh`; persist the full official `rslib` results and fresh host library hash.
4. Run all five real APKG integrations, including typed-answer coverage, against that host library.
5. Run fresh ARMHF cross-build plus ELF/ABI/GLIBC/export audit from the same source/Anki identity.
6. Supply the checksum-matching PW6 5.19.6 extracted rootfs and retained `pw6-rootfs.img`.
7. Run the image-derived exact-rootfs QEMU gate and persist new QEMU provenance.
8. Only then run package/reproducibility/privacy/content audit and persist the final ZIP, SHA-256, manifest, contents and complete reports.
9. Keep physical PW6 acceptance as the separate final HIL gate.

## Completion state

**Not released.** This checkpoint closes another provenance gap but does not satisfy the full current-head release chain.
