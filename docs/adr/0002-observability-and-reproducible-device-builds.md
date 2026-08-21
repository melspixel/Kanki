# ADR 0002 — Make observability and device-build identity first-class

- Status: Accepted
- Date: 2026-08-21
- Branch: `rewrite-v1`

## Context

The historical Kanki/RAnki patch line repeatedly required special builds to understand card rendering failures. At one point JavaScript layout logs were present but the promised `render-debug` directory was absent because the launcher and shim belonged to different build generations. The same line also used floating build inputs such as a `latest` KindleHF toolchain release.

Those failure modes make a Kindle application difficult to diagnose, reproduce and hand off. They also make it impossible to prove that a device result belongs to a particular source/toolchain combination.

The rewrite already requires a persistent Anki-style reviewer and source-owned Kindle native layer. Observability and reproducibility therefore belong inside the architecture rather than as temporary debugging patches.

## Decision

### 1. Diagnostics is a normal runtime component

The rewrite packages a source-owned `kanki-diag` daemon. It binds only to loopback (`127.0.0.1:17393`) and is started/stopped by the same launcher that owns the reviewer process.

A successful normal launch creates a fresh:

```text
/mnt/us/extensions/kanki/render-debug/
```

and retains at most one previous session at:

```text
/mnt/us/extensions/kanki/render-debug.previous/
```

Failure to create the directory or start the diagnostics daemon is an explicit launch failure. The application must not silently continue while claiming renderer observability exists.

### 2. Default renderer telemetry is privacy-safe and bounded

The reviewer reports only structural/layout metadata by default:

- bounded render/card identifier;
- question/answer side;
- card/body class;
- actual WebKit viewport, `#qa` and scroll geometry;
- device pixel ratio;
- bounded element tag/class plus computed font/display/position/geometry properties.

Default diagnostics do not scrape or transmit element text, note fields, AV source names, collection contents, credentials or account/device identifiers.

Both client and server impose session bounds so diagnostics cannot grow indefinitely on low-resource Kindle hardware.

### 3. Raw card source capture is explicit opt-in

Raw HTML/CSS/AV metadata may contain private study content. It is therefore disabled unless this sentinel exists before launch:

```text
/mnt/us/extensions/kanki/enable-render-capture
```

When enabled, capture is limited to the first 12 render sides and also subject to a server-side byte/request cap. The redacted `kanki-report.sh` bundle never includes raw captures automatically.

### 4. Build identity and manifests are mandatory

An installable rewrite package must contain `BUILD.json` and `MANIFEST.sha256`. Launch and sync refuse to continue when either is missing or the manifest does not verify.

`BUILD.json` records the Kanki source commit, Anki pin, Kindle system/toolchain reference, native audio dependency pins, target architecture and reviewer/diagnostics protocol versions.

### 5. Device toolchains must be pinned by immutable identity

CI/release workflows must not download a floating `latest` KindleHF toolchain. Kanki currently pins koxtoolchain `2026.08` and verifies the exact `kindlehf.tar.zst` SHA-256 before extraction.

The canonical installer lives at `tools/install_kindlehf_toolchain.sh`; workflows call that script instead of duplicating or improvising a toolchain URL.

### 6. CI infrastructure health is tested separately from product health

A minimal `Actions runner probe` workflow has no Kanki dependencies and exists only to prove that a GitHub-hosted runner can actually execute a shell step. If that job has no step list, red product workflows are not interpreted as product failures.

## Consequences

### Positive

- A device should not require another custom build merely to expose renderer geometry.
- The specific historical failure “diagnostic code ran but the debug folder did not exist” becomes a detectable launch error.
- Default reports can be shared without automatically disclosing study content.
- Raw card source remains available when explicitly needed for deep parity investigation.
- A future maintainer can reproduce the same ARMHF build inputs from repository state.
- CI infrastructure outages/quota failures are separated from compiler/test failures.
- Release evidence can be tied to one source/toolchain/package identity.

### Costs

- One additional small loopback daemon runs with the application.
- Diagnostic transport and storage need bounded contract tests and PW6 validation.
- Raw-source debugging requires an explicit sentinel/restart.
- Toolchain upgrades now require an intentional version/checksum update instead of automatically following `latest`.

## Rejected alternatives

### Keep diagnostics as a development-only shim

Rejected because it recreates mixed-version installations and makes handoff depend on undocumented special packages.

### Log entire card HTML and DOM text by default

Rejected because it creates unnecessary privacy exposure and large logs.

### Use a fixed logical viewport as the diagnostic/control mechanism

Rejected because the published Kindle WebKit exposes its own CSS-pixel/pixel-density mechanism; historical 420px rewriting caused real layout corruption.

### Continue using the latest cross-toolchain release

Rejected because an old source commit would no longer have a deterministic build environment and device ABI regressions would be difficult to attribute.

## Verification required

This ADR is an architecture decision, not proof of implementation correctness. Issue #11 remains the closure record. Before release, the exact candidate must demonstrate:

- host diagnostics privacy/bounds contract;
- ARMHF `kanki-diag` build and ABI gate;
- automatic debug-directory creation on PW6;
- metrics produced for real cards without element text;
- opt-in bounded raw capture;
- redacted bundle privacy review;
- checksum-pinned toolchain installation and package identity verification.
