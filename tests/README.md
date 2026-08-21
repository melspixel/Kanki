# Test contracts

Tests in this directory are cross-layer contracts for the rewrite. They are intended to prevent architecture regressions, not merely exercise one deck.

## Current groups

- reviewer contracts cover the persistent `#qa`, card classes, script
  execution, semantic AV ordering, navigation, generic old-WebKit CSS,
  bounded diagnostics and real pinned MathJax SVG;
- bridge integrations cover a pinned-Anki disposable collection, review/type
  answer/bury/reopen behavior, normal/full/media sync and the seven unchanged
  upstream APKG fixtures;
- source contracts enforce semantic typed bridge, audio, privacy and package
  invariants without substituting for executable integration;
- `anki_i18n_determinism_contract.py` authenticates the fixed upstream Anki
  i18n generator and its build-only ordered-map normalization;
- `rootfs_audit_source_contract.py` pins the PW6 firmware audit identity and
  evidence boundary; `tools/audit_pw6_rootfs.sh` supplies the corresponding
  executable loader/QEMU evidence;
- `install_integrity_contract.sh` proves that the installed runtime accepts
  only manifest-owned package files plus the bounded config/log/PID/diagnostic
  state allowlist, and rejects tampering, stale files and symlinks;
- `runtime_preflight_contract.py` keeps log, lock and report paths behind the
  authenticated install verifier;
- `operation_lock_contract.sh` executes collection-lock contention, exact
  launcher handoff and inherited-worker lifetime behavior; its source contract
  also requires the same helper to execute under the fixed PW6 BusyBox/flock
  rootfs audit;
- `report_privacy_contract.py` keeps redacted-report staging private, unique,
  failure-cleaned and atomically published without raw capture/user data;
- `reproducible_zip_contract.py` checks deterministic archive mechanics; two
  full canonical package builds remain the release evidence.

## Rules

- Never add a fixture whose expected behavior depends on a named user deck as a special case.
- Representative real decks/APKGs may be used as compatibility fixtures, but the implementation must remain generic.
- Source-contract tests do not replace executable integration tests; issue #11 records which verification level has actually passed.
- A cleanup that moves files must keep these tests runnable from the canonical host gate.
