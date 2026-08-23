# Current-head WebKit1 and native-host checkpoint — 2026-08-22

## Scope

This checkpoint executed the recovered WebKit1/browser compatibility group and the three native C production translation units from source commit:

```text
ece332e5de8ce6499e3603dcf6dd27c256819084
```

It is a targeted current-head static-gate checkpoint. It is not a complete `run-static-gates.sh` pass, an official Anki backend build, an ARMHF result, or release evidence.

## Source identity

Every input file was retrieved through the GitHub Git object API and checked locally with `git hash-object` before use. The complete expected/actual object table is persisted in:

```text
docs/logs/KAP_CURRENT_HEAD_WEB_NATIVE_20260822.log
SHA-256 1ac58bfaad499b55d97b468b11c7ac5709ea7ba080a2f703a321cbbd4c4d1f2a
```

The reviewer fixture used the repaired blob from commit `f0925bf767cf59708ef3ee72ebaaff046cdd6b1d`:

```text
tests/test_reviewer_runtime_fixtures.js
Git blob 557e094bd7969af8a367ecde6ce9f878c1ce6c2a
```

## Toolchain

```text
Node.js v22.16.0
cc (Debian 14.2.0-19) 14.2.0
Python 3.13.5
```

## Executed WebKit1/browser checks

```text
node --check web/audio_queue.js                         PASS
node --check web/bridge.js                              PASS
node --check web/css_compat.js                          PASS
node --check web/decks.js                               PASS
node --check web/reviewer.js                            PASS
node --check tests/test_reviewer_runtime_fixtures.js    PASS
node tests/test_audio_queue.js                          PASS
node tests/test_css_compat_fixtures.js                  PASS (9 fixtures)
node tests/test_web_contract.js                         PASS
node tests/test_reviewer_runtime_fixtures.js            PASS (10 fixture groups)
```

## Native C build and self-tests

Exact compile contract:

```sh
cc -O2 -std=c99 -Wall -Wextra -Werror -Icore native/app.c -ldl -o build/static-gates/kap-app-host
cc -O2 -std=c99 -Wall -Wextra -Werror native/audio.c -ldl -o build/static-gates/kap-audio-host
cc -O2 -std=c99 -Wall -Wextra -Werror -Icore native/sync.c -ldl -o build/static-gates/kap-sync-host
```

Results:

```text
kap-app --self-test-audio-supervision    PASS, elapsed_ms=1002
kap-audio --self-test                    PASS
kap-sync --self-test                     PASS
```

The app supervision test deliberately creates a child that ignores SIGTERM. The production host waited for the bounded grace interval, issued SIGKILL, reaped the child, cleared ownership, and returned successfully.

Host checkpoint binary SHA-256 values:

```text
kap-app-host    252dc9160dc4b8f3268d1e2b6f3067ddd3ce384ed5fbe240404d25c785720d30
kap-audio-host  16d699b756fc94aa277f08588ee302482164864731152ac37aeb75ac6fea2656
kap-sync-host   2af78280ca03ccb9064530a7b0c47bee723b5b77f254984c65553f7a354ab689
```

These x86-64 host binaries are transient test outputs and are not committed or eligible for packaging.

## Remaining release gates

Still required from one complete clean current-head Git checkout:

- remaining Python/shell static, lifecycle, sync, zombie-lock, package, rootfs and QEMU provenance regressions;
- official Anki 26.08.1 `cargo check`, full rslib test and release build;
- all five real APKG integrations against the fresh host library;
- KindleHF ARMHF rebuild and complete ELF/ABI/GLIBC/export audit;
- exact retained-image-derived PW6 QEMU for backend, audio and sync;
- package/privacy/reproducibility audit and final durable installer;
- separate physical PW6 HIL.

The exact private PW6 extracted rootfs plus retained `pw6-rootfs.img` remain absent. No release is claimed.
