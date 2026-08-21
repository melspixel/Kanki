# Kanki — native Anki reviewer for Kindle

Kanki is a source-owned Kindle front end around the **real, pinned Anki Rust backend**. It is being rewritten from first principles for Kindle hardware and Amazon's published userspace instead of extending the old RAnki binary with preload patches.

## Status

`rewrite-v1` is the new implementation line. The historical patched client remains on `main` until the replacement passes the hardware acceptance matrix. No release from this branch should overwrite a working installation unless it is explicitly marked as a device test build.

For local-Codex/zero-context takeover, read **`AGENTS.md` then `docs/CODEX_HANDOFF.md`**. For the documentation map, read `docs/README.md`. Current implementation/verification state lives in `docs/STATUS.md`; closure evidence is tracked in issue #11 and PR #10 remains Draft until that closure record is complete.

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

- `crates/` — Rust domain/host components. Audit each crate's production/test role before removing scaffolding.
- `bridge/` — typed semantic Anki review/sync C ABI.
- `device/` — source-owned Kindle GTK/WebKit, sync, diagnostics and audio executables.
- `assets/device` — deck/sync/reviewer shell pages.
- `assets/reviewer` — reviewer runtime and generic old-WebKit compatibility.
- `scripts/` — runtime scripts installed on Kindle.
- `tools/` — canonical build, local Docker, policy and developer tooling.
- `packaging/` — install-facing configuration and shortcuts.
- `tests/` — bridge/renderer/audio/diagnostics contracts.
- `third_party/anki` — exact Anki release used by production builds.
- `third_party/ranki-reference` — historical implementation reference; never linked or packaged.
- `third_party/kindle-sdk` — Kindle system/toolchain reference.
- `docs/` — architecture, status, local build, testing, parity and handoff documentation.

## Development

Initialize pins:

```sh
git submodule update --init --recursive
```

Host gates:

```sh
sh tools/run_host_gates.sh
```

Full local Kindle package (recommended while GitHub-hosted Actions are unavailable):

```sh
bash tools/local_package_docker.sh
```

The canonical full package recipe is `tools/build_kindle_package.sh`; CI and local builders must call the same script rather than maintaining duplicate build logic.

See `docs/TESTING.md` before producing or installing a device build.

## Handoff discipline

Before ending a substantial development session, update `docs/STATUS.md`, issue #11 and, when the next action/blocker changes, `docs/CODEX_HANDOFF.md`/`docs/RESUME.md`. Architecture changes require an ADR. A future maintainer should be able to continue using only the repository and GitHub history.

## License

AGPL-3.0-or-later. The pinned Anki backend is also AGPL. Third-party components retain their own notices.
