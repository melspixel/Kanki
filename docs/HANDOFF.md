# Maintainer handoff

A maintainer should be able to reproduce, diagnose and release Kanki without reconstructing chat history.

## Source-of-truth pins

The three gitlinks at `third_party/` are authoritative. Updating Anki requires a dedicated PR that:

1. changes the Anki gitlink;
2. records upstream release notes and schema/proto changes;
3. runs host, cross, ABI and device acceptance suites;
4. updates the compatibility matrix;
5. never changes the UI through opaque numeric service IDs.

## Build identity

Every package must contain:

- semantic version;
- Kanki git commit;
- Anki git commit;
- Kindle SDK git commit;
- target architecture;
- minimum required GLIBC;
- reviewer protocol version;
- SHA-256 manifest of packaged files.

The launcher must print these values before opening a collection and must refuse to run when component build IDs disagree.

## Diagnostic bundle

A single command must create a redacted ZIP containing:

- build identity;
- system fingerprint (no serial/account/Wi-Fi data);
- application log;
- current renderer metrics;
- exact backend-rendered card HTML and final reviewer packet for a bounded number of cards;
- no AnkiWeb token or user note database.

## Branch/release policy

- `main`: last hardware-accepted release.
- `rewrite-v1`: active replacement until acceptance closes.
- feature branches: focused changes with tests and ADR updates.
- tags: signed release source points; generated ZIPs come only from CI.

## Definition of handoff-ready

- no untracked manual build steps;
- all dependencies pinned;
- architecture decisions recorded;
- device rollback documented;
- test corpus and expected results committed;
- open limitations listed, not hidden in logs;
- at least one clean install and one upgrade tested on real hardware.
