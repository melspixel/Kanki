# Kanki Next status

Updated: 2026-08-21

| Milestone | State | Evidence |
|---|---|---|
| Upstream RAnki source/package pin | complete | `upstream.lock`, CI provenance audit |
| PW6 firmware/source oracle | complete (derived reports) | existing repository audit workflows and `evidence/` summaries |
| Root-cause analysis | complete for initial renderer failures | `docs/ROOT_CAUSE.md` |
| Native CSS-pixel scale module | implemented, host-tested | `src/kindle_webkit_scale.*`, `tests/test_scale.c` |
| Persistent reviewer shell | implemented, static-tested | `web/reviewer.*`, `tests/test_probe_contract.py` |
| ARMHF renderer probe | implemented; CI cross-build, ABI audit, package smoke test green | `src/render_probe.c`, `Kanki Next` workflow |
| Real-device renderer validation | pending | requires PW6 report and photographs |
| Anki 26.08 backend adapter | planned | reuse/replace work on `anki-26.08-backend` |
| Full reviewer/scheduler UI | planned | M1 |
| Audio, MathJax, typed-answer compatibility | planned | M2 |
| Sync-ready application | planned | M3 |

## Continuous-integration baseline

The branch CI now exercises three independent gates on every relevant change:

1. host compilation, unit tests, legacy-WebKit contract tests, and a portable package/checksum smoke test;
2. a fresh clone of the pinned RAnki source plus download and hash audit of its release package;
3. KindleHF ARM cross-compilation, ELF/GLIBC inspection, direct-link rejection for Lab126 APIs, KUAL packaging, and checksum verification.

The first complete baseline passed all three gates. Device execution remains a separate mandatory gate.

## Current blocking question

Does the user's actual PW6 expose the same pixel-density behavior as the pinned firmware oracle? The device probe must answer this before any global typography decisions are made.
