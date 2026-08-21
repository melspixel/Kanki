# Local build: bypass GitHub Actions

This is the supported fallback when GitHub-hosted Actions cannot execute jobs. It builds the same ARMv7 hard-float Kindle package from the checked-out repository on a developer machine, without relying on a GitHub runner.

## Why Docker is the default local path

The target is Kindle/PW6 ARMv7 hard-float, while the canonical cross-compiler is KOReader koxtoolchain's Linux-hosted KindleHF toolchain. Running the release recipe directly on macOS would introduce a second host toolchain path. Instead, the local builder runs an Ubuntu 24.04 environment and invokes the same `tools/build_kindle_package.sh` script that CI uses.

On Apple Silicon Macs the wrapper forces `linux/amd64`, because the pinned KindleHF toolchain is a Linux x86-64 host toolchain. Docker Desktop, OrbStack and Colima can emulate amd64. The first Anki build can be slow under emulation; later Cargo/toolchain downloads are cached in named Docker volumes.

## Requirements

1. A local checkout of `melspixel/Kanki` on branch `rewrite-v1`.
2. Git submodules initialized for the pinned project references.
3. Docker-compatible CLI and daemon: Docker Desktop, OrbStack, or Colima.
4. Internet access for the first build to obtain Ubuntu packages, Rust 1.92.0 dependencies, the checksum-pinned KindleHF toolchain, Anki translation submodules, Cargo crates, and pinned miniaudio source.

Initialize the project gitlinks once:

```sh
git checkout rewrite-v1
git pull --ff-only
git submodule update --init third_party/anki third_party/kindle-sdk third_party/audiobook-koplugin third_party/ranki-reference
```

## One-command package build

From the repository root:

```sh
bash tools/local_package_docker.sh
```

The wrapper:

1. builds `tools/local-builder.Dockerfile` as Ubuntu 24.04 + Rust 1.92.0;
2. forces `linux/amd64` unless `KANKI_LOCAL_PLATFORM` overrides it;
3. mounts the checkout read/write at `/work`;
4. reuses named Docker volumes for Cargo and KindleHF downloads;
5. calls the canonical `tools/build_kindle_package.sh` recipe;
6. performs manifest, exported-symbol and target-GLIBC gates;
7. restores the temporary source injection into the Anki submodule even when the build fails.

Successful outputs are written to:

```text
out/local-kindle/Kanki-rewrite-hw3.zip
out/local-kindle/Kanki-rewrite-hw3.zip.sha256
out/local-kindle/package-contents.txt
out/local-kindle/package-exports.txt
out/local-kindle/package-glibc.txt
out/local-kindle/sysroot-glibc.txt
out/local-kindle/toolchain-info.txt
```

`BUILD.json` inside the ZIP records the exact repository commit, Anki pin, Kindle SDK pin, audiobook helper pin, miniaudio pin, koxtoolchain version/checksum, target triple and the canonical builder script.

## Canonical Linux recipe without Docker

On an Ubuntu 24.04 x86-64 host that already has the dependencies and Rust 1.92.0 installed, run:

```sh
bash tools/build_kindle_package.sh
```

The script deliberately requires the pinned source gitlinks and refuses a dirty root checkout by default. A diagnostic-only build from a dirty checkout can be forced with:

```sh
KANKI_ALLOW_DIRTY=1 bash tools/build_kindle_package.sh
```

Do not use a dirty build as release evidence.

## Relationship to GitHub Actions

`.github/workflows/package.yml` must invoke `tools/build_kindle_package.sh`; the workflow must not carry a separate copy of the compilation/package recipe. This keeps local and CI build logic from drifting.

A local green package is valid engineering evidence that the source/toolchain path can build, but it does not by itself close the release gates. The final candidate still needs same-commit evidence for the host/bridge/renderer gates and PW6 hardware acceptance recorded in issue #11.

When GitHub Actions is unavailable, record local build evidence with:

- exact commit SHA;
- host Mac model/architecture and Docker engine/version;
- builder image platform (`linux/amd64` by default);
- `toolchain-info.txt`;
- ZIP SHA-256;
- package ABI/GLIBC evidence files;
- whether the build ran from a clean checkout.

## Troubleshooting

If Docker reports an architecture warning on Apple Silicon, confirm that amd64 emulation is enabled and leave `KANKI_LOCAL_PLATFORM=linux/amd64`. Do not switch to an ARM64 builder unless a separately checksum-pinned ARM64-host KindleHF toolchain is introduced and documented.

If the build is interrupted, rerun the same command. Cargo and KindleHF downloads are cached. The builder restores the temporary `third_party/anki/rslib` bridge injection with a shell trap, so repeated builds must not accumulate source edits.

If the package script reports a pin mismatch, do not bypass it. Update the checkout/submodules to the commit documented by `docs/RESUME.md` and retry.
