# Handoff — Kanki Next bootstrap

## Scope completed

This checkpoint establishes the renderer foundation for a new Kindle-native Anki reviewer. It does not claim the full scheduler/sync application is complete.

Completed:

- pinned and audited upstream RAnki source/package;
- consumed the existing official PW6 firmware and source oracles;
- isolated the primary scaling/lifecycle causes of the rendering failures;
- implemented a reusable Lab126 WebKit scale module;
- implemented a standalone ARMHF renderer probe;
- implemented a persistent ES5 `#qa` reviewer shell;
- added host tests, upstream provenance checks, cross-build/ABI checks, portable package/checksum smoke tests, and device-report scripts;
- documented architecture, test plan, status, and exact next steps.

## Pinned inputs

Read `upstream.lock` before changing dependencies.

- RAnki source commit: `d671ee657f0c411474d2afff3bf9cbb49be2fb44`
- observed release: `v0.2`
- Anki backend target: `26.08`
- PW6 platform: `Bellatrix4`
- observed firmware: `5.19.6`
- source baseline: WebKitGTK `1.4.2`, GTK+ `2.20.1`

## Reproduce locally

```sh
cd projects/kanki-next
make clean test
```

Expected final lines:

```text
test_scale: ok
test_probe_contract: ok
test_audit_ranki: ok
```

## Build artifact

The `Kanki Next` GitHub Actions workflow produces:

```text
kanki-next-render-probe.zip
kanki-next-render-probe.zip.sha256
probe-build-report.txt
```

Do not install an uninspected binary. Verify the checksum and the CI ABI report first.

The green CI baseline produced an ELF32 ARM EABI5 hard-float executable with interpreter `/lib/ld-linux-armhf.so.3`. Its only direct runtime dependencies are `libdl.so.2` and `libc.so.6`, and its maximum imported GLIBC symbol version is `GLIBC_2.4`. Lab126 WebKit APIs remain runtime-resolved with `dlsym`, so the binary does not link directly against Amazon-specific symbols. The package checksum file is relative-path and remains verifiable after download/extraction.

## Device test

1. Back up `/mnt/us/anki_data`; the probe does not intentionally touch it, but a backup is inexpensive.
2. Extract `kanki-next/` to `/mnt/us/extensions/kanki-next/`.
3. Launch `Kanki Next renderer probe` in KUAL.
4. Photograph the page before and after **Show answer**.
5. Exit.
6. Run `Collect Kanki Next report`.
7. Retrieve `/mnt/us/documents/KankiNextProbeReport.txt`.
8. Compare its renderer density, `innerWidth`, breakpoints, and font/image measurements against `docs/TEST_PLAN.md`.

## Immediate next engineering task

Do not begin by tuning global fonts. First validate the native scale probe on the user's PW6.

After a passing device report:

1. create a persistent production reviewer window using the same scale module;
2. define a versioned C adapter around the Anki 26.08 backend branch;
3. open a copied test collection read-only where possible;
4. render one queued card's question/answer into the persistent `#qa` document;
5. add answer buttons and scheduler transitions;
6. capture the exact backend HTML, reviewer payload, and computed layout;
7. only then migrate audio, typed answers, hints, and MathJax.

If the native probe fails, use the report to determine whether the real device differs from the firmware oracle before changing layout constants.

## Known risks

- Lab126 extension signatures are inferred from exported symbols and ARM call sites; the probe is the first safe runtime validation.
- WebKitGTK 1.4-era JavaScript/CSS support remains limited even after DPI is correct.
- The Anki 26.08 ARMHF backend must be verified against the exact device GLIBC/runtime before production integration.
- E-ink refresh behavior and partial rendering are intentionally deferred until layout correctness is established.
