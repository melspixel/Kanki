# VM platform-reference checkpoint — 2026-08-22

## Scope

This checkpoint implements a narrowly scoped Kindle platform improvement from
current source. It does not claim a complete current-head static-gate, official
Anki, ARMHF, exact-rootfs QEMU or release pass.

Starting branch head:

```text
ae349e0126bc95d4350acc6885e4ee443a91c88e
```

Code/test checkpoint before this report:

```text
21f39b86b99e31182f7815bcc0bd707b4e75bbd5
```

Persisted log checkpoint:

```text
8affe8d75a37f350441f71c1b36e84694374a3be
```

## Reference-first engineering decision

The Kindle platform layer is no longer treated as an undocumented blank slate.
The following implementations were audited at pinned commits and recorded in
`docs/REFERENCE_IMPLEMENTATIONS.md`:

```text
crazy-electron/ranki       d671ee657f0c411474d2afff3bf9cbb49be2fb44
kbarni/kindlepuzzles       9f67dd04634d16dfa2e8eeef13eb582b8225e49e
emlyn-m/em-dash            f8c260636dc4fa811c7e470b8b4626985a188172
anakod/kindle-explorer     134d04e20d4eaa83a51369eaa80fd3fa007a4d46
```

Observed, independently rebuilt behavior:

- Lab126/Awesome application identity encoded in the GTK window title;
- `com.lab126.keyboard` open/close protocol;
- open value format `<application-id>:<layout>:<mode>`;
- direct `/usr/bin/lipc-set-prop -s ...` execution without a shell;
- waiting for and reaping the command child.

Ranki, em-dash and Kindle Explorer are reference-only because a repository
license file was not established during this audit. KindlePuzzles/Gargoyle code
showed GPL-2.0-or-later notices, but this checkpoint still uses independently
written code instead of copying or linking that implementation. Ranki remains
neither a runtime nor build dependency.

## Production changes

### Native host

New `native/app_platform.inc` provides:

```text
KAP_APP_ID = com.melspixel.kindleankiport
KAP_WINDOW_TITLE = L:A_N:application_ID:com.melspixel.kindleankiport_PC:N
KAP_LIPC_SET_PROP = /usr/bin/lipc-set-prop
KAP_KEYBOARD_PUBLISHER = com.lab126.keyboard
```

The adapter:

- parses exact versioned `kap://v1/<operation>` names;
- handles `ime/open` and `ime/close`;
- closes IME before reveal, back and application close;
- executes `lipc-set-prop` with `execl()` and no `/bin/sh`;
- bounds the child wait and force-reaps a wedged child;
- normalizes a keyboard potentially left visible by a crashed former process;
- suppresses duplicate open/close requests after state is known;
- closes IME through the normal application cleanup path.

`native/app.c` preserves the existing semantic reviewer fragment and composes
platform wrappers around only `dispatch_uri`, `load_decks` and `stop_audio`.
The GTK title call is preprocessed to the Lab126 application identity without
forking the rest of the window-construction code.

### Persistent reviewer

New `web/ime.js` loads after `bridge.js` and before `reviewer.js`. It:

- observes focus/blur for `#kap-type-answer`;
- uses capture plus WebKit `focusin`/`focusout` fallback;
- de-duplicates duplicate focus event paths;
- emits `ime/open` and `ime/close` over the existing versioned bridge;
- closes before `review/reveal`, non-question UI states, back and close.

Official Anki continues to perform typed-answer extraction/comparison. The new
code only connects WebKit focus to the Kindle system keyboard.

### CI quota control

`.github/workflows/kindle-anki-port.yml` is now manual-only:

```yaml
on:
  workflow_dispatch:
```

This preserves the reproducibility definition while preventing every source or
documentation commit from consuming exhausted hosted-runner quota. The Linux VM
remains the primary compiler.

## Maintained regression gates

New tests:

```text
tests/test_ime_runtime.js
tests/test_platform_adapter.c
tests/test_platform_reference_contract.py
```

`run-static-gates.sh` now executes all three. The C regression executes itself
through `/proc/self/exe` as a fake `lipc-set-prop`, so it verifies the actual
argument vector without a shell or a Kindle dependency.

Verified command sequence:

```text
-s com.lab126.keyboard close com.melspixel.kindleankiport
-s com.lab126.keyboard open  com.melspixel.kindleankiport:abc:1
-s com.lab126.keyboard close com.melspixel.kindleankiport
```

The duplicate second open is intentionally absent.

## Commands executed in the isolated Linux VM

```sh
node --check web/ime.js
node tests/test_ime_runtime.js

gcc -O2 -std=c99 -Wall -Wextra -Werror \
  tests/test_platform_adapter.c \
  -o tests/test-platform-adapter
./tests/test-platform-adapter

# A separate composition harness compiled the new app.c include/macro layout,
# executed its window-title and dispatch wrappers, and inspected preprocessor
# output for the Lab126 identity.
gcc -O2 -std=c99 -Wall -Wextra -Werror native/app.c \
  -o native/platform-composition-test
./native/platform-composition-test

gcc -E -P native/app.c
python3 -m py_compile tests/test_platform_reference_contract.py
python3 tests/test_platform_reference_contract.py
```

## Results

```text
web/ime.js syntax                                      PASS
IME focus/blur/reveal/state/back ordering              PASS
maintained C platform adapter, C99 -Werror             PASS
startup stale-keyboard close                           PASS
open argument vector                                   PASS
duplicate open suppression                             PASS
reveal-time close before semantic dispatch             PASS
bounded child execution/reaping path                   PASS
native app composition harness, C99 -Werror            PASS
Lab126 window-title preprocessor substitution          PASS
reference/license/independence contract                PASS
manual-only workflow contract                          PASS
```

Persisted combined log:

```text
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
SHA-256 42b0059bc09828ae077ab926cb9a23121dbcfff27720ffebf4767b67c413692a
```

Additional local checkpoint hashes:

```text
maintained test source
  9d7670ffc20f0733c0cb3316692b42cba429a4cc887f0313c45cfaae7cfc80d0
maintained test binary
  973ac2668606b2e63b65019ec87be0b2e9437ce3746d292dc43d216a17280612
maintained test log
  300778921628860ba397da315493c9d52b200b335e5708b3b56892717dbcdff2
```

The binary hash is transient host evidence and is not a release artifact.

## Commit chain

```text
7baa73d8c76fc735e1a889c458a821d17f327f7e  manual-only workflow
9a7ed9bf00a6e56e27ae0a68195ffc38a09a4446  reference/attribution policy
9cc5c573d2637a924803f220146efc02b8834c3d  initial native platform adapter
5a3afd88cc033bdd5b26cf212d7836bab47a3049  native host composition
bb00a8f6df5d10c41c75edb43b715139d46ac281  WebKit IME adapter
cefac2e2501e546c599f01639dd4fbaf45940f34  reviewer load order
f0e8a50750653eb2d4c9f269919ee95c7d337c79  IME runtime fixture
dd7af67c631b64894d7d589cf4e0d631662ba53b  static-gate wiring
7ce0cc07771e492db5fd5d5c6b41d207cea75bd1  injectable command constants
4492b0930d99a80fca56d396a84446166951edaa  platform reference contract
66e6060737bc2c9ba9c33a5601f62271f9261253  contract gate wiring
ed183d639ecfc90e37f6fe0bec84b1752d1e8d6c  stale-keyboard normalization
33c499950fb898cc531d216679a24fc4b917563b  executable C regression
21f39b86b99e31182f7815bcc0bd707b4e75bbd5  C regression gate wiring
8affe8d75a37f350441f71c1b36e84694374a3be  persisted combined log
```

## Environment limitation and next exact step

The isolated VM still cannot use ordinary outbound networking. DNS queries,
normal Git/curl access and direct-IP GitHub probes failed, so Rust 1.92.0,
Cargo dependencies, protoc, QEMU, debugfs and KindleHF cannot yet be installed
through normal package/download channels. This checkpoint therefore does not
claim the complete translation-unit/static gate from a full current clean
checkout.

Next execution order:

1. materialize a complete clean Git checkout of the new live head into the VM;
2. import or install the pinned offline toolchain/dependency bundle;
3. run the complete `run-static-gates.sh`, including the new maintained tests;
4. rerun official Anki host tests and five real APKG integrations;
5. rebuild ARMHF and audit ELF/ABI/GLIBC/exports;
6. obtain the exact private PW6 rootfs tree and retained image;
7. run image-derived QEMU and only then package.

## Completion semantics

This is a green, durably persisted **platform-reference checkpoint**. It is not
a final installer, exact-rootfs QEMU result or physical PW6 HIL result.
