# Release gates

A release is produced only when all non-hardware gates pass.

1. Independence: no prohibited implementation/runtime dependency.
2. Upstream pin: exact official Anki commit and source anchors verified.
3. Core: host and ARMHF builds; named ABI symbols; strict warnings.
4. Reviewer: scripts, AV markers, type answer, body classes, CSS ownership,
   nested-scroll flattening and page navigation tests.
5. Lifecycle: repeated start/raise/exit, stale PID and interrupted-audio tests.
6. Package: manifest, checksums, ABI/GLIBC ceiling, no user data/secrets.
7. Hardware acceptance: PW6 rendering, touch, keyboard, Bluetooth reroute,
   suspend/resume and 50-cycle relaunch matrix.

Hardware acceptance is evidence collected on the target device; CI completion
must not be represented as that evidence.
