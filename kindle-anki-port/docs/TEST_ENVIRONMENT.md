# Kindle Anki Port — Test Environment

Updated: 2026-08-22

## Goal

Provide a reproducible porting laboratory that separates desktop-Anki semantics, ARM/Linux compatibility, exact PW6 runtime ABI, release packaging, and real-device behavior. VM/QEMU evidence may close non-hardware gates, but it is never a substitute for physical PW6 acceptance.

The official Kindle open-source tree is useful for understanding and rebuilding open components; it is not a complete emulator. High-fidelity runtime testing additionally requires the checksum-matching PW6 5.19.6 rootfs/proprietary runtime files. For release L2, both the extracted rootfs directory and the retained rootfs image are required: the directory supplies QEMU's runtime tree, while the image supplies the full-filesystem SHA-256 identity. Those bytes are private external inputs and are never committed to GitHub.

## Release-order invariant

The maintained non-hardware release sequence is strictly:

```text
L0 host semantics/static contracts
-> L1 ARMHF cross-build + ELF/ABI/GLIBC audit
-> L2 exact checksum-matching PW6 rootfs-image + extracted-rootfs QEMU
-> L2.5 QEMU-bound package/reproducibility/privacy audit
-> durable GitHub release artifacts
```

A final-looking `Kindle-Anki-Port-PW6-armhf.zip` must **not** be assembled before L2 passes for the exact ARMHF bytes being archived. Generic ARM/QEMU host sanity is not a substitute for L2, and an extracted directory that is not bound to the canonical rootfs-image SHA-256 is not sufficient L2 evidence.

## Test layers

### L0 — Host semantic and deterministic contract tests

Runs natively in the VM/container.

- build/test the pinned official Anki `rslib`;
- run collection, scheduler, rendering, typed-answer, cloze, AV, bury, close, and sync-protocol fixtures;
- test the named `kap_*` C ABI;
- test reviewer state transitions without GTK/WebKit;
- run JavaScript syntax/DOM/CSS compatibility fixtures;
- run launcher/sync lifecycle and operation-lock regressions;
- run package-policy/reproducibility **fixtures**;
- run build/QEMU/package provenance and orchestration contract tests.

Package tests at L0 use synthetic fixtures only. A synthetic ZIP is test evidence, not a release artifact.

### L1 — ARMHF cross-build and static ABI audit

Uses the pinned KindleHF toolchain and generated/verified sysroot inputs.

- compile `libanki-kindle.so`, `kap-app`, `kap-audio`, and `kap-sync` for ARMv7 hard-float;
- verify ELF class, EABI/hard-float attributes, interpreter, dynamic dependencies and exported `kap_*` symbols;
- reject host-library leakage;
- enforce the target GLIBC ceiling;
- inspect RPATH/RUNPATH and unresolved symbols;
- persist `ARMHF-GATES.txt`, `BUILD-PROVENANCE.txt`, file/export/ABI/GLIBC reports and exact binary hashes.

L1 may run generic static ARM/QEMU sanity, but it does **not** create the final installer. No physical Kindle is required.

### L2 — Exact PW6 rootfs QEMU runtime gate

Runs the fresh L1 ARM binaries against an extracted PW6 5.19.6 rootfs under `qemu-arm`/`qemu-arm-static`, while requiring the retained source rootfs image from the same verified extraction.

Required identity checks occur before QEMU execution:

```text
clean project HEAD == BUILD_COMMIT
Anki identity == upstream.lock.json pin
ARMHF-GATES.txt == ARMHF gates: PASS
ARMHF source/Anki provenance matches the release identity
rootfs manifest bytes == committed canonical PW6 5.19.6 manifest
ROOTFS_IMAGE is present as a regular retained image
rootfs image SHA-256 == canonical manifest rootfs_image.sha256
```

Runtime checks include:

- verify the full rootfs-image SHA-256 and selected loader/libc/WebKit hashes against the canonical manifest;
- load the real target dynamic linker/shared libraries from the extracted tree;
- load the exact `libanki-kindle.so` built at L1;
- smoke-test backend startup/C ABI loading and shutdown;
- run `kap-audio --self-test` and `kap-sync --self-test` under the exact rootfs;
- detect missing symbols and incompatible target-library assumptions;
- persist `QEMU-SMOKE.txt`, rootfs verification, backend/audio/sync logs and `QEMU-PROVENANCE.txt`.

`QEMU-PROVENANCE.txt` records source/Anki identity, canonical manifest hash, canonical rootfs-image SHA-256 and the SHA-256 of all four ARMHF release binaries. It records hashes/identifiers only and does not expose private rootfs/image absolute paths.

The rootfs tree and image are external private inputs and are never committed to GitHub.

### L2.5 — Release package, provenance, privacy and reproducibility gate

This layer may run **only after L2 PASS**.

`package-and-audit.sh` requires the fresh L2 evidence directory and independently verifies:

```text
QEMU smoke PASS
PW6 rootfs verification PASS
rootfs-verification.txt proves canonical rootfs-image SHA-256
QEMU provenance rootfs_verified=true
same source commit
same pinned Anki commit
same canonical rootfs-manifest SHA-256
same canonical rootfs-image SHA-256
same SHA-256 for libanki-kindle.so, kap-app, kap-audio and kap-sync
backend/audio/sync smoke PASS
```

Then it may:

- stage the installer from maintained source plus the verified L1 binaries;
- generate and verify the internal SHA-256 manifest;
- reject collections, media, credentials, logs, PID/lock state and user configuration;
- normalize modes/timestamps/member order for reproducibility;
- run ZIP integrity/content/policy audit;
- persist ARMHF/QEMU/rootfs/ABI/GLIBC/package provenance reports alongside the ZIP;
- record canonical rootfs-manifest and rootfs-image hashes in package provenance;
- generate the external ZIP SHA-256 and package contents listing.

The production package path must fail closed on absent or stale L2 evidence.

### L3 — Virtual Kindle service laboratory

Provides test-only platform adapters for target services not meaningfully reproduced by user-mode QEMU.

- virtual framebuffer/Xvfb/Xephyr surface;
- scripted touch/key events;
- mock Lab126 CSS-pixel/full-content-zoom API;
- mock e-ink refresh requests with call-order assertions;
- mock DBus/framework focus and single-instance activation;
- fake Bluetooth/audio-route events;
- fake suspend/resume and low-memory signals;
- fake network/AnkiWeb protocol server;
- deterministic virtual clock.

Mocks must be selected only through test build/runtime paths. Production packages must not depend on preload shims or mock libraries.

### L4 — Renderer fixture tests

Uses a persistent reviewer shell and representative fixture content.

Fixture matrix includes:

- short text and long dictionary cards;
- image-heavy and mixed CJK/Latin cards;
- `card1`/`card2` selectors;
- inline script cards;
- local/remote AV tags;
- typed answer and cloze typed answer;
- hint and MathJax cards;
- nested overflow/long-page cards;
- deliberately unsupported modern-template cases.

Evidence may include backend-rendered HTML/CSS/AV packets, final DOM/body classes, geometry/scroll-root traces, renderer errors, question/answer traces and sanitized screenshots/rasterized output.

### L5 — Hardware-in-the-loop PW6 acceptance

Runs only on an actual PW6.

- e-ink waveform, ghosting, partial/full refresh and latency;
- real touch paging/calibration and on-screen keyboard/IME focus;
- Kindle framework fullscreen/focus/leave-and-reenter behavior;
- real Bluetooth pairing, `mixersink` routing, disconnect/reconnect and audible output;
- suspend/resume, power button, USB mode, Wi-Fi, thermal/battery/OOM behavior;
- repeated launch/raise/exit/relaunch matrix;
- final visual review of representative real cards.

L5 is the only layer that can claim hardware acceptance.

## Canonical inputs and provenance

The environment must pin/verify:

- official Anki source commit;
- Rust/toolchain/protoc inputs used by the release build;
- KindleHF toolchain release/checksum;
- exact PW6 firmware checksum;
- exact retained PW6 rootfs-image SHA-256;
- canonical PW6 runtime-file hashes from the extracted tree;
- generated sysroot manifest where used;
- real APKG fixture hashes in the final test report;
- source, ARMHF, QEMU and package provenance hashes.

Canonical PW6 manifest:

```text
testenv/qemu/pw6-5.19.6-rootfs-manifest.json
```

Firmware/rootfs-image/extracted proprietary library bytes are never committed. Only scripts, expected hashes, manifests and sanitized derived reports belong in GitHub.

## Maintained release entrypoints

The public interfaces must encode the same ordering and image identity as the production gates:

```text
make qemu-smoke ROOTFS=<verified extracted tree> ROOTFS_IMAGE=<retained verified image>
  -> requires both private inputs
  -> writes QEMU evidence to $(QEMU)

make package
  -> requires $(QEMU)
  -> package-and-audit.sh revalidates source/Anki/manifest/rootfs-image/ARMHF evidence

vm-advance.py without --rootfs
  -> may stop at armhf-checkpoint-passed
  -> must not create final ZIP

vm-advance.py with --rootfs
  -> also requires --rootfs-image
  -> exact QEMU cannot begin from an unbound extracted tree

vm-advance.py with --rootfs + --rootfs-image but incomplete required real-APKG coverage
  -> may stop at qemu-checkpoint-passed
  -> must not create final ZIP

vm-advance.py with all semantic + ARMHF + exact-rootfs-image QEMU gates green
  -> may package
  -> may record non-hardware-release-gates-passed
```

Public GitHub Actions do not possess the private PW6 rootfs tree/image. The canonical workflow therefore persists a `NOT-A-RELEASE.txt` host/ARMHF build checkpoint and intentionally does not create the final installer.

## What the VM can complete without the user's local host

Given the required public/pinned build inputs and the verified private rootfs tree **plus retained rootfs image** mounted into the VM, the VM can perform:

- all source editing/code generation;
- host Rust/C/JavaScript tests;
- five-real-APKG integration;
- ARMHF cross-compilation;
- ELF/ABI/GLIBC/export audits;
- exact-rootfs QEMU L2;
- mocked service integration;
- QEMU-bound installer assembly/privacy/reproducibility audit;
- release reports/checksums and GitHub persistence.

The user's Mac is not required for ordinary compilation, QEMU, or packaging.

If the VM cannot itself obtain the private checksum-matching PW6 rootfs tree/image pair, a local/Codex worker may only transport those verified private inputs according to `CODEX_COORDINATION.md`. Compilation remains VM-owned.

## What cannot be truthfully validated in the VM

These require the physical Kindle:

1. real e-ink waveform/ghosting/refresh artifacts and latency;
2. actual touch controller behavior and on-screen keyboard focus;
3. Amazon framework window/focus behavior when leaving fullscreen/reopening;
4. real Bluetooth pairing and audible route switching through the device stack;
5. suspend/resume, power-button, USB-storage, Wi-Fi, thermal, battery and OOM behavior;
6. proprietary services dependent on live `/dev` nodes or framework/DBus processes.

A local host is needed only as a bridge when the VM cannot reach the Kindle over USB/SSH.

## Local-host / Codex collaboration contract

When hardware testing eventually starts, the local worker must first read `CODEX_COORDINATION.md`, verify the final installer/test-bundle hashes recorded in `HANDOFF.md`, and collect only sanitized HIL evidence. It must not rebuild the software locally as a substitute for the VM release provenance.

Before hardware testing, Task B in `CODEX_COORDINATION.md` may be used only to provide the checksum-verified private PW6 5.19.6 extracted rootfs and retained rootfs image to the VM/private channel.

## Completion rule

The virtual environment can close all non-hardware gates only when L0 -> L1 -> L2 -> L2.5 are green for one coherent current source/Anki/ARMHF/runtime identity and the final artifacts/reports are persisted durably. L2 specifically requires proof of the canonical retained rootfs-image SHA-256. The VM must never mark PW6 hardware acceptance complete without L5 evidence.
