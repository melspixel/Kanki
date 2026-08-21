# Local VM build status

Updated: 2026-08-21

## Green gates

The independent port now builds from the exact pinned official Anki 26.08.1
source (`e5a6fbe27fdd4d57d5f712191b4a753032e57853`) using the verified offline
bundle and Rust 1.92.0.

### Static/platform gates

`testenv/scripts/run-static-gates.sh` passes:

- Python/injector/semantic-boundary/package tests;
- ES5 reviewer syntax and persistent-reviewer contract tests;
- strict `-Wall -Wextra -Werror` host builds of `kap-app`, `kap-audio`, and
  `kap-sync`;
- audio and sync self-tests;
- repeated-launch/stale-PID/backup lifecycle tests.

### Official Anki backend gates

The semantic bridge is installed as `crate::services::kap_bridge`, a child of
the generated-services module, so it can call only the deliberately wrapped
private backend methods without exposing numeric dispatch or reimplementing
Anki behavior.

Verified successfully:

```text
cargo check -p anki --features rustls --lib --offline
cargo test -p anki --features rustls kap_port::tests --lib --offline
cargo build -p anki --features rustls --release --offline
```

The release `libanki.so` exports 18 named `kap_*` functions, including review,
typed-answer, bury, normal sync, full sync, media status, and abort operations.

### Real collection integration

`tests/test_core_integration.py` passed against copied, disposable collections
from all five source decks:

- 4000 Essential English Words;
- Advanced Vocabulary Complete (typed-answer path exercised);
- COCA-English;
- New Oriental IELTS disorder edition;
- Baicizhan postgraduate entrance vocabulary.

The test opens each collection through official rslib, reads a study deck,
retrieves queued cards, renders question/answer, extracts AV metadata, rates a
card through the official scheduler, buries additional cards, checks health,
and closes the collection.

### ARMHF gate

The official backend and all three native programs cross-compile with
koxtoolchain 2025.05 for ARMv7 hard-float:

```text
libanki-kindle.so  ELF32 ARM EABI5 hard-float; max GLIBC_2.18
kap-app             ELF32 ARM EABI5 hard-float; max GLIBC_2.4
kap-audio           ELF32 ARM EABI5 hard-float; max GLIBC_2.4
kap-sync            ELF32 ARM EABI5 hard-float; max GLIBC_2.4
```

The WebKit host now follows the Kindle native scale contract: W3C CSS pixels
are enabled before WebView creation, device pixel density is queried, and a
non-1 density is applied only with full-content zoom. This prevents text-only
zoom from separating typography and image scale.

## Still open

- assemble and audit the install archive from the exact committed source;
- persist ordinary source files and release evidence in the canonical GitHub
  branch;
- QEMU/rootfs runtime smoke tests;
- renderer fixture expansion, MathJax/hint/TTS coverage, and sync protocol
  fixtures;
- physical PW6 hardware-in-the-loop acceptance.
