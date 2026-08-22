# Kindle Anki Port — Current Progress

Updated: 2026-08-22 UTC

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Independent product boundary | complete | official Anki owns semantics; no Ranki/rewrite/preload runtime |
| Reference/attribution policy | complete | pinned implementations and license handling in `docs/REFERENCE_IMPLEMENTATIONS.md` |
| Ordinary GitHub source | complete | maintained source under `kindle-anki-port/` |
| GitHub Actions quota control | complete | Kindle workflow is manual-only; VM is primary compiler |
| Kindle window identity | targeted current-source green | Lab126/Awesome application title composed into native host |
| Typed-answer IME platform bridge | targeted current-source green | focus/blur, open/close, startup normalization, reveal cleanup and direct LIPC argv tested |
| Persistent reviewer/WebKit contracts | targeted current-source green | audio queue, CSS 9 fixtures, reviewer 10 groups, IME runtime fixture pass |
| Native host/audio/sync host subset | targeted current-source green | strict C/self-tests and lifecycle checkpoints exist; one complete current-head static invocation pending |
| Sync/collection ownership | hardened | wrapper-death, zombie-owner and collection exclusivity regressions fixed |
| Official Anki semantic bridge | hardened + historical full green | deterministic overlay enforced; historical rslib 539/539; final clean-head rerun required |
| Five real APKG integration | historical green | reviewer lifecycle, typed answer and AV observed; final clean-head rerun required |
| Git/source identity | hardened | resolvable clean `HEAD^{commit}` and successful status required |
| Anki working-tree provenance | hardened | exact pinned HEAD plus deterministic overlay only |
| Cargo target provenance | hardened | host/ARMHF recreate gate-owned Anki target directory |
| ARMHF/ABI/GLIBC | historical green | hard-float outputs below target ceiling; final current-head rebuild required |
| PW6 rootfs identity | hardened, private input absent | exact extracted rootfs plus retained full image required |
| Exact-rootfs QEMU | gate hardened, dynamic rerun pending | runtime must be freshly `rdump`ed from verified image |
| Package privacy/reproducibility | gate hardened, final run pending | package is forbidden before matching exact-rootfs QEMU |
| Final current-head ZIP | incomplete | old ZIP is stale; no release may be claimed |
| Physical PW6 HIL | not started | separate final gate after software hashes exist |

## Latest targeted checkpoint

Report:

```text
docs/VM_PLATFORM_REFERENCE_20260822.md
```

Persisted log:

```text
docs/logs/KAP_PLATFORM_REFERENCE_20260822.log
SHA-256 42b0059bc09828ae077ab926cb9a23121dbcfff27720ffebf4767b67c413692a
```

Implemented and tested:

```text
Lab126 window title/application identity                  PASS
web typed-answer focus -> ime/open                        PASS
blur/reveal/non-question/back/close -> ime/close          PASS
startup stale-keyboard normalization                      PASS
duplicate focus/open de-duplication                       PASS
direct execl lipc-set-prop argument vector                PASS
bounded command child wait/reap                           PASS
C99 -Wall -Wextra -Werror maintained platform test        PASS
JavaScript runtime test                                   PASS
reference/license/independence contract                   PASS
manual-only workflow contract                             PASS
```

The maintained executable C regression uses `/proc/self/exe` as a controlled
fake `lipc-set-prop`, verifying this exact order:

```text
close com.melspixel.kindleankiport
open  com.melspixel.kindleankiport:abc:1
close com.melspixel.kindleankiport
```

No second open is emitted for duplicate focus events.

## Current test evidence classification

### Current-source targeted evidence

```text
IME web/native platform adapter             PASS
reviewer runtime fixtures                   PASS (10 groups)
CSS compatibility fixtures                  PASS (9)
audio queue lifecycle                       PASS
WebKit1 source/runtime contracts             PASS
native app/audio/sync strict host subset     PASS
launcher/sync/zombie lifecycle subsets       PASS
provenance and package/rootfs regressions    PASS (synthetic/contract level)
```

### Historical full evidence requiring final rerun

```text
official Anki rslib                          539 passed, 0 failed
five real APKG integrations                  PASS
typed answer and AV in real APKG             observed
kap-app / kap-audio / kap-sync               ARM EABI5 hard-float
libanki-kindle.so                            max GLIBC_2.18
PW6 target libc ceiling                      GLIBC_2.35
```

Historical evidence demonstrates feasibility but is not final release
provenance after later hardening.

## Exact target identity

```text
Anki commit               e5a6fbe27fdd4d57d5f712191b4a753032e57853
Anki release              26.08.1
Rust target               armv7-unknown-linux-gnueabihf
Kindle compiler triple    arm-kindlehf-linux-gnueabihf
KindleHF release          2025.05
PW6 firmware              5.19.6 / 4832160042
firmware MD5              697aeb33c02f46b9b0911ab05c28b06d
firmware SHA-256          72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
rootfs image SHA-256      b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
loader SHA-256            a089ca56fba8e33fb8d87b791ac9f81c9065d0ae9d9d0ffb899037f7ed284701
libc SHA-256              5a34d04c0392bf6b69b361ffab68b8c2a064b444a4c6c58891a3607bd4593431
WebKitGTK SHA-256         6bbe5a102d7500deb1ce109f3df22360b4b50f8d9d52da2fcf462700655a6810
GLIBC ceiling             2.35
```

## Current infrastructure blockers

The isolated VM has usable CPU, memory, disk and root access. The active blocker
is input/toolchain transport:

```text
ordinary DNS/Git/curl             unavailable
direct-IP GitHub probes           unavailable
complete live Git checkout        not materialized locally
Rust 1.92.0/Cargo cache           absent
protoc/qemu/debugfs/patchelf       absent
KindleHF 2025.05                   absent
private PW6 rootfs tree/image      absent
```

Repeated independent probes confirm the networking failure. This does not
permit lowering tests or moving compilation to the user's local host.

## Next execution sequence

1. Resolve the newest live branch HEAD.
2. Materialize its complete Git objects and clean worktree in the VM.
3. Restore networking or import the pinned offline build/dependency bundle.
4. Run full current-head static gates, including the real `native/app.c` build.
5. Run official Anki check, 539 tests and release build; hash host library.
6. Run all five real APKG integrations.
7. Rebuild and audit all four ARMHF outputs.
8. Verify exact rootfs and retained image; run image-derived QEMU backend/audio/sync.
9. Package only after QEMU, repeat privacy/reproducibility/content audit and persist release assets.
10. Run separate physical PW6 HIL.

## Release state

**Not released.**

The historical installer SHA-256
`9449bdcfadd961827af3527bb05e2a8069afe4f44a15081c9316e78be7443225`
remains stale and prohibited as a final artifact.
