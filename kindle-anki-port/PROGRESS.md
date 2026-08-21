# Kindle Anki Port — Current Progress

Updated: 2026-08-21

## Phase summary

| Workstream | State | Evidence / blocker |
|---|---|---|
| Product boundary and source map | complete | Independent desktop-Anki reviewer port; official Anki 26.08.1 pinned |
| Architecture | complete enough to implement | Official rslib + semantic C ABI + Kindle native host + persistent ES5 reviewer |
| Source skeleton | substantial, not canonicalized | Verified source ZIP exists; ordinary GitHub source tree still needs materialization |
| Rust semantic adapter | implemented draft, build failing | Latest diagnostic: 26 errors from private generated backend service methods |
| Kindle native host | implemented draft | Host C syntax/strict-warning gate passed in temporary build environment; no ARM/device validation |
| Web reviewer | implemented draft | Persistent `#qa`, AV controls, typed input, paging and compatibility code exist; parity suite incomplete |
| Audio | unresolved backend choice | Archive contains miniaudio; Kindle-native GStreamer/mixersink path must be integrated and tested |
| Sync | incomplete | Launcher script references `kap-sync`; executable/source implementation is absent |
| Automated tests | insufficient | Only two small Rust parser tests in archived source; complete integration/lifecycle/package tests missing |
| Host build | blocked | Semantic adapter visibility/API boundary must be refactored |
| ARMHF cross-build | not reached | Depends on green host backend build |
| Package/release | not started successfully | No accepted installer, checksum, ABI report, or GitHub release asset |
| PW6 acceptance | not started | Requires produced package and target-device run |

## Latest compile blocker

The adapter is injected as `rslib/src/kap_port.rs` at crate root. It attempts to call generated `Backend*Service` methods. In the pinned Anki version, those generated methods are private to the backend module. Rust therefore reports E0624 for operations including:

- AV extraction;
- note/field retrieval;
- cloze extraction and answer comparison;
- deck tree/current deck/collapse;
- queue retrieval and rendering;
- interval description;
- answer and bury.

The E0282 type-inference errors are downstream effects.

### Repair direction

Do not expose all generated service methods publicly. Add a small backend-owned bridge module with deliberate `pub(crate)` functions, or invoke stable collection-level methods while holding `Backend::with_col`. Keep the external C ABI named and semantic.

## Build strategy after Actions quota exhaustion

- Iterative `cargo check`, tests, release build and ARMHF cross-build run in the VM/container.
- Every meaningful checkpoint is committed to `melspixel/Kanki:kindle-anki-port` and summarized in `HANDOFF.md`.
- Reproducible scripts and logs are committed or attached to the final GitHub release.
- GitHub Actions is reserved for a final independent rerun when quota is available; it is not the primary compiler during development.

## Definition of the next green checkpoint

The next checkpoint is achieved only when all of the following are true:

1. ordinary source files are present in the canonical GitHub branch;
2. the semantic adapter compiles against the pinned Anki source;
3. host tests cover at least collection open, deck tree, queue/render, typed answer, answer, bury, and close;
4. a release `libanki.so` exports the expected named `kap_*` ABI;
5. `HANDOFF.md` records exact commands, commit, logs, and remaining failures.

## Completion definition

Software release completion requires:

- complete maintainable source in GitHub;
- green host and ARMHF builds;
- ABI/GLIBC and package-policy audit;
- `Kindle-Anki-Port-PW6-armhf.zip` plus SHA-256, manifest and test report persisted on GitHub;
- no RAnki/rewrite-v1/preload dependency and no user data or credentials in the package.

PW6 hardware acceptance is a separate final gate and must be recorded honestly rather than inferred from CI.
