# Release gates

Software delivery is produced only when all non-hardware gates pass for one coherent current-head provenance chain. Historical green checkpoints may guide regression work, but they cannot be promoted into current release evidence.

1. Independence: no prohibited implementation/runtime dependency; official Anki owns collection, scheduler, renderer semantics, sync, media and undo.
2. Source/upstream identity: clean project `HEAD == BUILD_COMMIT`; exact official Anki commit and source anchors verified.
3. L0 host semantics/static: complete static contracts plus official Anki backend/semantic tests are green from that source identity.
4. Real APKG integration: all five maintained real-APKG fixtures pass, including typed-answer coverage, against the same backend identity.
5. L1 ARMHF/ABI: `libanki-kindle.so`, `kap-app`, `kap-audio` and `kap-sync` are rebuilt for ARMv7 hard-float; ELF, exports, dependency, RPATH/RUNPATH and GLIBC ceilings pass and exact binary hashes are persisted.
6. L2 exact-rootfs QEMU: those exact ARMHF bytes are tested with both the checksum-matching PW6 5.19.6 extracted rootfs and retained full rootfs image. The supplied extracted tree is independently verified, the retained image SHA-256 must match the canonical manifest, and the actual QEMU `-L` runtime tree must be freshly produced with `debugfs rdump` from that verified retained image. Rootfs/runtime verification, backend, audio and sync smokes pass and QEMU provenance binds source, Anki, canonical manifest, canonical rootfs-image hash, `rootfs_runtime_source=verified-image-rdump`, and all four binary hashes.
7. L2.5 package/privacy/reproducibility: only after L2 PASS, assemble `Kindle-Anki-Port-PW6-armhf.zip`; revalidate the QEMU evidence, canonical rootfs-image identity, image-derived runtime provenance, internal manifest, binary hashes, privacy policy and reproducibility.
8. Durable release evidence: persist the final ZIP, external SHA-256, contents listing, internal manifest and complete host/APKG/ARMHF/QEMU/package reports on GitHub.

A final-looking `Kindle-Anki-Port-PW6-armhf.zip` must not be assembled before the exact-rootfs L2 gate passes for the exact ARMHF bytes that will be archived. An extracted rootfs directory without proof of the canonical retained rootfs-image SHA-256 is not sufficient L2 evidence, and neither is a canonical image hash paired with QEMU execution against an independently supplied directory. Public CI without the private checksum-matching PW6 rootfs tree/image may emit a clearly labelled checkpoint only; it must not create the final installer.

A new L2 attempt must invalidate prior dynamic PASS/provenance before runtime work begins. A failed rerun must therefore leave no older `QEMU-SMOKE.txt` or `QEMU-PROVENANCE.txt` that could be consumed by packaging.

## Hardware acceptance — separate from software delivery

PW6 hardware-in-the-loop acceptance starts only after the software-release artifact and its hashes are durably recorded. It covers real rendering/e-ink behavior, touch/keyboard, Bluetooth/audio rerouting, suspend/resume and the relaunch matrix.

Hardware acceptance is recorded as a distinct physical-device result. VM/QEMU PASS can close the non-hardware software gates, but can never be represented as PW6 hardware evidence; conversely, pending HIL does not authorize bypassing or weakening any software release gate above.
