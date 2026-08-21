# Kanki — native Anki reviewer for Kindle

Kanki is a source-owned Kindle front end around the **real, pinned Anki Rust backend**. It is being rewritten from first principles for Kindle hardware and Amazon's published userspace instead of extending the old RAnki binary with preload patches.

## Status

`rewrite-v1` is the new implementation line. The historical patched client remains on `main` until the replacement passes the hardware acceptance matrix. No release from this branch should overwrite a working installation unless it is explicitly marked as a device test build.

For current implementation/verification state, read `docs/STATUS.md`. For zero-context takeover, read `docs/RESUME.md`. Closure evidence is tracked in issue #11 and PR #10 remains Draft until that closure record is complete.

Current pinned references:

- Anki `26.08.1`: `e5a6fbe27fdd4d57d5f712191b4a753032e57853`
- RAnki reference only: `d671ee657f0c411474d2afff3bf9cbb49be2fb44`
- Kindle SDK: `b4a6c99d718a7cf74935f36105c62491b4336a61`

## Non-negotiable design rules

1. The application is built from source; it never patches or redirects a prebuilt RAnki executable.
2. Anki scheduling, rendering, sync and collection semantics come from the pinned Anki backend, not a reimplementation.
3. The reviewer owns one persistent WebKit document with `#qa`, matching desktop Anki's lifecycle. Question/answer changes replace `#qa` content; they do not reload the page.
4. Kindle DPI and CSS pixels use Lab126's native WebKit extensions when present. There is no hard-coded `420px` viewport and no global font scaling.
5. Kanki never contains deck-specific selectors such as `.word`, `.pos-badge` or a named deck. Card typography belongs to the note type.
6. Compatibility rules may target semantic reviewer controls such as replay buttons, but must not resize arbitrary SVG, images or text.
7. Every build is self-identifying, reproducible, diagnosable and safe to hand over.
8. `/mnt/us/anki_data` is user data and is never replaced or deleted by install, upgrade, rollback or diagnostics.

## Repository map

- `crates/kanki-domain` — review state machine and stable front-end data model.
- `crates/kanki-backend` — application-facing backend abstractions.
- `crates/kanki-renderer` — persistent reviewer packet/document policy.
- `crates/kanki-platform` — platform boundary.
- `crates/kanki-app` — executable and self-test entry point.
- `bridge/` — typed semantic Anki review/sync C ABI.
- `device/` — source-owned Kindle GTK/WebKit, sync and audio executables.
- `assets/device` — deck/sync/reviewer shell pages.
- `assets/reviewer` — reviewer runtime and generic old-WebKit compatibility.
- `third_party/anki` — exact Anki release used by production builds.
- `third_party/ranki-reference` — historical implementation reference; never linked or packaged.
- `third_party/kindle-sdk` — extraction/toolchain reference.
- `docs/` — architecture, decisions, status, handoff and closure gates.

## Development

```sh
git submodule update --init --recursive
cargo fmt --all -- --check
cargo clippy --workspace --all-targets -- -D warnings
cargo test --workspace
cargo run -p kanki-app -- --self-test
python3 tools/check_policy.py
```

Use the GitHub workflows as the canonical recipes for typed Anki and KindleHF builds. Do not create a separate undocumented packaging procedure.

See `docs/TESTING.md` before producing or installing a device build.

## Handoff discipline

Before ending a substantial development session, update `docs/STATUS.md`, issue #11 and, when the next action/blocker changes, `docs/RESUME.md`. Architecture changes require an ADR. A future maintainer should be able to continue using only the repository and GitHub history.

## License

AGPL-3.0-or-later. The pinned Anki backend is also AGPL. Third-party components retain their own notices.
