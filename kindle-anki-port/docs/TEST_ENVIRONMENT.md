# Kindle Anki Port — Test Environment

Updated: 2026-08-21

## Goal

Build a reproducible test environment that separates desktop-Anki semantics, ARM/Linux compatibility, Kindle runtime ABI, and real-device behavior. The environment is a porting laboratory, not a substitute for target-device acceptance.

The official Kindle source tree is useful for rebuilding open-source components and understanding API contracts, but source alone is not a complete emulator. The exact firmware rootfs and proprietary Lab126 runtime services are also needed for high-fidelity ABI and runtime tests.

## Test layers

### L0 — Host semantic tests

Runs natively in the VM/container.

- build the pinned official Anki `rslib`;
- run collection, scheduler, rendering, typed-answer, cloze, AV, bury, close, and sync-protocol fixture tests;
- test the named `kap_*` C ABI;
- test reviewer state transitions without GTK/WebKit;
- run JavaScript syntax, DOM-contract, CSS-compatibility, lifecycle-shell, and package-policy tests.

This layer must be fast and deterministic.

### L1 — ARMHF cross-build and static ABI audit

Uses the pinned KindleHF toolchain and a generated sysroot.

- compile `libanki-kindle.so`, `kap-app`, `kap-audio`, and `kap-sync` for ARMv7 hard-float;
- verify ELF class, EABI, interpreter, CPU attributes, dynamic dependencies, and exported `kap_*` symbols;
- reject host-library leakage;
- enforce the target GLIBC ceiling;
- inspect RPATH/RUNPATH and unresolved symbols;
- unpack and audit the installation archive.

No physical Kindle is required.

### L2 — QEMU user-mode runtime

Runs ARM binaries against an extracted, checksum-verified PW6 rootfs under `qemu-arm`/`qemu-arm-static`.

- load the real target dynamic linker and shared libraries;
- open a disposable copied Anki collection;
- exercise the C ABI and scheduler/rendering lifecycle;
- smoke-test process startup, IPC, manifest verification, and clean shutdown;
- detect missing symbols and incompatible GLIBC/library assumptions.

The rootfs is an external input and is never committed to GitHub.

### L3 — Virtual Kindle service laboratory

Provides test-only platform adapters for services unavailable in QEMU.

- virtual framebuffer and Xvfb/Xephyr display surface;
- scripted touch/key events;
- mock Lab126 CSS-pixel/full-content-zoom API;
- mock e-ink refresh requests with call-order assertions;
- mock DBus/framework focus and single-instance activation;
- fake Bluetooth/audio-route events;
- fake suspend/resume and low-memory signals;
- fake network and AnkiWeb protocol server;
- deterministic virtual clock.

Mocks are selected by a test build/runtime flag. Production packages must not depend on preload shims or mock libraries.

### L4 — Renderer fixture tests

Uses a persistent reviewer shell and a representative fixture collection.

Fixture matrix:

- short plain-text card;
- long dictionary card;
- image-heavy card;
- mixed CJK/Latin card;
- `card1`/`card2` selectors;
- inline script card;
- local and remote AV tags;
- typed answer and cloze typed answer;
- hint card;
- MathJax inline/display;
- nested overflow and long-page card;
- deliberately unsupported modern template.

Evidence collected:

- backend-rendered HTML/CSS/AV packets;
- final DOM/body classes;
- computed geometry and scroll root;
- screenshot or rasterized page;
- JavaScript/renderer errors;
- question/answer transition trace.

### L5 — Hardware-in-the-loop PW6 acceptance

Runs only on the actual Kindle.

- e-ink waveform, ghosting, partial/full refresh, and latency;
- real touch paging and calibration;
- on-screen keyboard and IME focus;
- Kindle framework fullscreen/focus/leave-and-reenter behavior;
- real Bluetooth pairing, `mixersink` routing, disconnect/reconnect, and audible output;
- suspend/resume, power button, USB mode, Wi-Fi transitions, low-memory behavior;
- 50-cycle launch/raise/exit/relaunch matrix;
- final visual review of representative real cards.

This is the only layer that can claim hardware acceptance.

## Proposed repository layout

```text
kindle-anki-port/testenv/
├── README.md
├── Makefile
├── container/
│   └── Dockerfile
├── scripts/
│   ├── fetch-pinned-anki.sh
│   ├── prepare-sysroot.sh
│   ├── run-host-gates.sh
│   ├── run-armhf-gates.sh
│   ├── run-qemu-smoke.sh
│   └── package-and-audit.sh
├── qemu/
│   ├── entrypoint.sh
│   └── rootfs-manifest.json
├── mocks/
│   ├── lab126/
│   ├── framework/
│   ├── audio/
│   ├── eink/
│   └── network/
├── fixtures/
│   ├── collections/
│   ├── media/
│   └── renderer/
├── tests/
│   ├── core/
│   ├── reviewer/
│   ├── lifecycle/
│   ├── sync/
│   └── package/
└── hil/
    ├── device-agent.sh
    ├── host-bridge.sh
    └── acceptance-matrix.md
```

## Inputs and provenance

The environment must pin and verify:

- official Anki source commit;
- KindleHF toolchain release and checksum;
- exact PW6 firmware/rootfs checksum;
- Kindle open-source bundle checksum;
- generated sysroot manifest;
- fixture collection hashes;
- test environment container digest.

Firmware/rootfs/proprietary library bytes are not committed. Only scripts, expected hashes, manifests, and derived reports are stored in GitHub.

## What the VM can complete without the user's local host

- all source editing and code generation;
- host Rust/C/JavaScript tests;
- ARMHF cross-compilation;
- ELF/ABI/GLIBC audits;
- QEMU user-mode execution against an available rootfs;
- mocked GTK/WebKit/Lab126/service integration;
- sync protocol fixtures and optional real-network tests with injected secrets;
- installation-package assembly and privacy audit;
- reproducibility reports and GitHub persistence.

## What cannot be truthfully validated in the VM

These require the physical Kindle, not specifically the user's Mac:

1. real e-ink waveform, ghosting, refresh latency, and display artifacts;
2. actual touch controller behavior and on-screen keyboard focus;
3. Amazon framework window/focus behavior when leaving fullscreen and reopening;
4. real Bluetooth pairing and audible route switching through the device audio stack;
5. suspend/resume, power-button, USB-storage, Wi-Fi, thermal, battery, and OOM behavior;
6. device-specific proprietary services that depend on `/dev` nodes or live DBus/framework processes.

A local host is needed only as a bridge when the VM cannot reach the Kindle over USB/SSH. Compilation itself does not require the user's host.

## Local-host / Codex collaboration contract

When hardware testing starts, Codex on the user's host should:

1. read `kindle-anki-port/CODEX_COORDINATION.md` and this file;
2. verify the package SHA-256;
3. copy the installation package and test agent to the Kindle;
4. run scripted device tests over USBNetwork/SSH when available;
5. prompt the user only for irreducibly physical actions such as Bluetooth pairing, hearing audio, touching the screen, and pressing the power button;
6. collect logs, framebuffer captures, system fingerprints, and the completed acceptance matrix;
7. commit only sanitized reports to GitHub.

## Completion rule

The virtual test environment may close all non-hardware release gates. It must never mark PW6 acceptance complete without evidence from L5.
