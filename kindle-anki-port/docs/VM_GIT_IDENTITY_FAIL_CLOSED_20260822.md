# VM Git identity fail-closed hardening — 2026-08-22

## Scope

This audit continued from branch head `f0894f6ede6458f876064cb4e8add10cbcce5034` after reading `HANDOFF.md`, `PROGRESS.md`, `CODEX_COORDINATION.md`, and `docs/TEST_ENVIRONMENT.md`.

The goal was to inspect the release provenance chain after the retained-image/image-derived-QEMU-runtime hardening. No full current-head build is claimed here: ordinary `git clone` in the execution container still fails DNS resolution for `github.com`, and the checksum-matching private PW6 5.19.6 extracted rootfs plus retained image are not mounted.

## Defect found

The host-backend, ARMHF and exact-rootfs-QEMU gates previously used the equivalent of:

```sh
PROJECT_HEAD=$(git -C "$PROJECT" rev-parse HEAD)
if [ -n "$(git -C "$PROJECT" status --porcelain --untracked-files=all -- .)" ]; then
    # dirty
fi
```

This was not fully fail-closed. A Git ref can still print a 40-hex object name after the referenced commit object has disappeared/cannot be resolved. `git status` then exits non-zero. Because the failing command was nested inside command substitution used as the argument to `[ -n ... ]`, Bash `set -e` did not reliably convert that failure into a gate failure; an empty substitution could be interpreted as a clean tree.

`package-and-audit.sh` had an additional release-critical gap: its Git-source check was optional (`if PROJECT_HEAD=$(git ...); then ... fi`). Therefore a non-Git copied project tree could reach packaging while declaring an arbitrary syntactically valid 40-hex `BUILD_COMMIT`. This matters because the final ZIP copies maintained source assets (`web/`, `scripts/`, config/docs/launchers) in addition to already-gated ARMHF binaries. Those archived source bytes therefore also require a verifiable Git identity.

## Fix

The production gates now require an actually resolvable commit object:

```sh
git -C "$PROJECT" rev-parse --verify 'HEAD^{commit}'
```

and explicitly test the exit status of the cleanliness check before inspecting its output:

```sh
if ! PROJECT_STATUS=$(git -C "$PROJECT" status --porcelain --untracked-files=all -- . 2>/dev/null); then
    # fail closed
fi
```

The host and ARMHF gates also require the pinned Anki checkout HEAD to resolve as a commit object via `HEAD^{commit}`. Packaging now requires a Git checkout unconditionally; copied/non-Git source trees and repositories whose HEAD object cannot be resolved are rejected with status 66 before ZIP construction.

Changed production blobs after this hardening:

```text
testenv/scripts/run-armhf-gates.sh       aeee9ba7f5759ce44b161c8669111f527a3dc0b2
testenv/scripts/run-host-backend-gates.sh 1efcdd18b017deed1b76871e1d598715eb298e56
testenv/scripts/run-qemu-smoke.sh        1bd183e72a1d6490eac36cb5a165c75074efd62a
testenv/scripts/package-and-audit.sh     9d41690315b8dcaa8333d2a6fe0cd2bc3b10f4b0
```

## Regression coverage

Existing test suites were extended rather than adding a parallel release path:

```text
tests/test_armhf_provenance.py           9208c15a1ac243a413057abab5c550f0400a006c
tests/test_host_backend_provenance.py    9137193089492ba5834cd35613ceddae0a09e271
tests/test_qemu_provenance.py            6ff2672ac10772437f73e1cd35e8fa6b38867a87
tests/test_package_reproducibility.py    dfd005fa252f9f9211a6def7a2873439df77d527
```

Coverage added:

- ARMHF: missing PROJECT HEAD commit object is rejected before Cargo; missing Anki HEAD commit object is rejected before Cargo.
- Host backend: the same project/Anki missing-object cases are rejected before injection/Cargo.
- QEMU: missing project HEAD commit object is rejected before dynamic L2 and cannot leave `QEMU-SMOKE.txt`.
- Packaging: the fixture is now a real Git repository; a copied non-Git project and a repository with the loose HEAD commit object deleted are both rejected before package construction.

All four tests are already part of `testenv/scripts/run-static-gates.sh`, so no separate opt-in wiring is required.

## Targeted dynamic reproducer

Because the execution container still cannot materialize the complete branch through normal Git networking, a small local Git repository was used to reproduce the shell/Git failure mode directly. The executed cases were:

```text
case=clean_resolvable PASS
case=dirty_detected PASS
case=plain_rev_parse_missing_object PASS (old prerequisite can be fooled)
case=old_status_substitution_failure_ignored PASS (reproduced old fail-open behavior)
case=verify_commit_missing_object_rejected PASS
case=nongit_package_source_rejected PASS
case=all PASS
```

Persisted evidence:

```text
docs/logs/KAP_GIT_IDENTITY_TARGETED_20260822.log
SHA-256 649526115118aa93996b3e66f75fff77111e0d0abee506bff167cb6cc0da13d7
```

The central reproduction sequence was equivalent to:

```sh
git init -q repo
git -C repo config user.name fixture
git -C repo config user.email fixture@example.invalid
printf 'tracked\n' > repo/tracked.txt
git -C repo add tracked.txt
git -C repo commit -qm fixture
head=$(git -C repo rev-parse HEAD)
obj=repo/.git/objects/${head:0:2}/${head:2}
rm "$obj"

git -C repo rev-parse HEAD
# still prints the ref value

bash -e -c 'if [ -n "$(git -C "$1" status --porcelain -- .)" ]; then :; fi; echo survived' _ repo
# reproduces the old fail-open status-substitution behavior

git -C repo rev-parse --verify 'HEAD^{commit}'
# fails, which is now a release-gate failure
```

## Commits

Sequential commits in this hardening pass:

```text
5f976086761d6e68897b3575eb639fa82f94b269  harden ARMHF git identity checks
d97d2b2010046976ed71f7f09d07536470335e80  harden host backend git identity checks
ddc6c5b0d64fd4bcec1f7e3b59fabaad04563c60  harden QEMU git identity checks
28c048566e818fa1abb88b69bcda9eb9d06a9399  require resolvable Git source for packaging
669e34075a245ae6ecec36d880ba3fac65bdcd8b  test package Git source identity
74c674ed64a621c50e0861982002c75f1d221d14  test ARMHF missing Git objects fail closed
4195a05127f9168474f044fd4c3b449ae0b0f8d0  test host missing Git objects fail closed
591536e2a18c913d62c5b715942bdf5f204b7229  test QEMU missing Git object fails closed
02c77fb4cb756349c698a58b4e36d9fa2651297a  persist targeted Git identity reproducer
```

## Environment limitation and claims

A normal clone attempt still fails in the execution container:

```sh
git clone --depth 1 --branch kindle-anki-port --single-branch \
  https://github.com/melspixel/Kanki.git /tmp/Kanki
```

with:

```text
fatal: unable to access 'https://github.com/melspixel/Kanki.git/': Could not resolve host: github.com
rc=128
```

Therefore this report does **not** claim a complete current-head static-gate run, official Anki `rslib` rerun, five-real-APKG rerun, ARMHF rebuild, ABI/GLIBC audit, exact-rootfs QEMU run, or final package. The targeted reproducer validates this specific Git failure mode only.

The private PW6 inputs also remain absent:

```text
checksum-matching extracted PW6 5.19.6 rootfs
retained pw6-rootfs.img
expected image SHA-256 b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
```

## Ordered next actions

1. Resolve the then-current branch head in a network-capable build VM and materialize a complete ordinary Git checkout with its commit objects intact.
2. Run the complete static gate suite; the new missing-object/non-Git package regressions must pass there.
3. From the same clean source identity and exact Anki 26.08.1 pin, rerun official backend tests and all five real APKG integrations.
4. Rebuild ARMHF and rerun ELF/ABI/GLIBC/export audits.
5. Supply the checksum-matching private extracted rootfs **and** retained image, then run the image-derived exact-rootfs QEMU L2 gate.
6. Only after L2 PASS, run package/reproducibility/privacy/content audit and persist a new final ZIP, SHA-256, contents, internal manifest and complete reports.
7. Physical PW6 acceptance remains a separate later HIL result.

## Release status

**Not released.** The stale historical ZIP SHA-256 `9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225` remains invalid for final delivery.
