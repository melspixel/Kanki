# VM package/privacy hardening — 2026-08-22

## Scope

The installer is assembled from a clean staging tree, but the release auditor must also fail closed if transient Kindle runtime state is ever accidentally introduced into a future packaging path.

## Hardened state rejection

`tools/audit_package.py` and `tests/test_package_policy.py` now reject all of the following from a release ZIP:

```text
config.ini
*.log
*.pid
*.anki2
.sync-request
.opened-build
collection.media/**
.kap-operation.lock/**
.kap-operation.lock.pid.*
```

This extends the previous exact-name checks so pre-sync/pre-upgrade collection backups cannot leak merely because their basename is not exactly `collection.anki2`.

The `.kap-operation.lock.pid.*` pattern is especially relevant after the lifecycle hardening: it is the short-lived sibling file used for atomic sync-worker ownership publication and must never be distributable state.

## Regression coverage

`tests/test_package_audit.py` now creates deliberately contaminated ZIPs and requires rejection for:

- `backups/collection-pre-sync-*.anki2`;
- `.kap-operation.lock/pid`;
- `.kap-operation.lock.pid.<pid>`;
- `.sync-request`;
- `.opened-build`;
- `collection.media/<file>`.

A targeted VM execution of the committed audit logic returned:

```text
audit_package: ok sha256=ab6bbf82437a2e2ee1030205800ea8c242759c8699d25fa1e450c9d560c74039
package-runtime-state regressions: ok
```

The SHA above belongs only to the synthetic test ZIP and is not a product package hash.

## Commits

```text
07bab167932d1028193fbf72624e19a8910fd8cf  audit: reject transient collection and lock state
bbd1e15da07ba5a1d54a4909627e674dcceecaa5  test: reject transient lifecycle state from packages
5dbb090826eeb477a511d451ecc475269a560848  test: cover backup and operation-lock package leakage
```

## Release status

This closes a privacy/audit gap but does not make the existing package checkpoint final. The installer still needs to be regenerated from the final canonical branch head after the complete host/backend/APKG/ARMHF sequence and exact PW6 rootfs QEMU smoke.
