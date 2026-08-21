# Local build: bypass GitHub Actions

This is the supported fallback when GitHub-hosted Actions cannot execute jobs. It builds the same ARMv7 hard-float Kindle package from the checked-out repository on a developer machine, without relying on a GitHub runner.

## Why Docker is the default local path

The target is Kindle/PW6 ARMv7 hard-float, while the canonical cross-compiler is KOReader koxtoolchain's Linux-hosted KindleHF toolchain. Running the release recipe directly on macOS would introduce a second host toolchain path. Instead, the local builder runs an Ubuntu 24.04 environment and invokes the same `tools/build_kindle_package.sh` script that CI uses.

On Apple Silicon Macs the wrapper forces `linux/amd64`, because the pinned KindleHF toolchain is a Linux x86-64 host toolchain. Docker Desktop, OrbStack and Colima can emulate amd64. The first Anki build can be slow under emulation; later Cargo/toolchain downloads are cached in named Docker volumes.

## Requirements

1. A local checkout of `melspixel/Kanki` on branch `rewrite-v1`.
2. Git submodules initialized for the pinned project references.
3. Docker-compatible CLI and daemon: Docker Desktop, OrbStack, or Colima.
4. Internet access for the first build to obtain Ubuntu packages, Rust 1.92.0 dependencies, the checksum-pinned KindleHF toolchain, Anki translation submodules, Cargo crates, pinned miniaudio source, the checksum-pinned MathJax 2.7.9 archive, and host-test-only Node/jsdom dependencies.

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
3. mounts the checkout at `/work`;
4. marks mounted repositories as safe Git directories inside the container;
5. reuses named Docker volumes for Cargo and KindleHF downloads;
6. calls the canonical `tools/build_kindle_package.sh` recipe;
7. performs manifest, exported-symbol and target-GLIBC gates;
8. restores the temporary source injection into the Anki submodule even when the build fails.

Successful outputs are written to:

```text
out/local-kindle/Kanki-rewrite-hw3.zip
out/local-kindle/Kanki-rewrite-hw3.zip.sha256
out/local-kindle/package-contents.txt
out/local-kindle/package-exports.txt
out/local-kindle/package-glibc.txt
out/local-kindle/sysroot-glibc.txt
out/local-kindle/toolchain-info.txt
out/local-kindle/mathjax-info.txt
out/local-kindle/archive-info.txt
```

`BUILD.json` inside the ZIP records the exact repository commit, Anki pin, Kindle SDK pin, audiobook helper pin, miniaudio pin, MathJax version/checksum, source commit epoch, koxtoolchain version/checksum, target triple and the canonical builder script. `archive-info.txt` records that epoch, the sorted archive file count and the final archive SHA-256.

The canonical recipe creates the ZIP from sorted regular-file paths with fixed
permissions and the source commit time. Source checkout mtimes and package-tree
creation order therefore do not affect the archive. A host contract checks
this property, but release evidence still requires two clean full builds of
the exact candidate and a byte comparison.

## PW6 5.19.6 rootfs ABI audit

After building the canonical package from a clean checkout, audit that exact
candidate against Amazon's published PW6 userspace:

```sh
bash tools/local_pw6_rootfs_audit.sh
```

The wrapper initializes the fixed nested KindleTool gitlink, builds
`tools/pw6-rootfs-audit.Dockerfile`, and invokes the canonical read-only audit
in `tools/audit_pw6_rootfs.sh`. On the first run it downloads the
412,492,749-byte official PW6 5.19.6 recovery bundle into ignored
`out/firmware/`, verifies its fixed SHA-256, extracts and verifies the rootfs
and the firmware's TTS squashfs, then reuses that authenticated cache. All
additional Linux packages are installed only in the Docker image; no host
global package installation is required.

The audit refuses a dirty checkout or a package whose `BUILD.json` candidate
does not equal `HEAD`. It checks every packaged ELF for ARMv7 hard-float,
compares required GLIBC/GCC/LIBATOMIC symbol versions with the rootfs, resolves
package plus GTK2/GObject/WebKitGTK/X11/GStreamer dependency closures with the
PW6 loader, and executes the device UI/backend and audio capability probes via
QEMU/chroot. The TTS squashfs is staged at `/usr/lib/tts` to model the firmware
runtime mount; it is not patched or copied into the Kanki package.

Evidence is written below:

```text
out/firmware/pw6-5.19.6/evidence/<candidate-sha>/
```

`SUMMARY.txt` must say `pw6_rootfs_audit=pass` and always records
`hardware_execution=not_run`. This is strong loader/ABI evidence, but it does
not emulate a display server, audio hardware, Lab126 service behavior or
Kindle geometry. It never mounts or modifies `/mnt/us`, and no Amazon firmware
or proprietary runtime bytes enter the release ZIP.

## Typed Anki host bridge and disposable collection

The package build proves the ARMHF library can compile, but it cannot execute
that library on the x86-64 builder. Run the separate native Linux host gate to
exercise the semantic C ABI against a disposable collection:

```sh
sh tools/local_anki_bridge_docker.sh
```

The thin Docker wrapper calls the canonical Linux recipe:

```text
tools/run_anki_bridge_host.sh
```

It builds the pinned Anki backend as a native `libanki.so`, injects a host-only
fixture binary into the pinned source checkout for the duration of the build,
and creates a nine-card collection under a `mktemp` directory using Anki's own
typed APIs. Five default-deck cards exercise queue counts, question/answer
rendering, separate question/answer sound and TTS extraction, `{{FrontSide}}`,
basic typed-answer comparison, Again/Hard/Good/Easy persistence, user bury,
close/reopen and health checks. A sixth card is created in a normal deck with
both playback settings disabled and gathered into a filtered deck; the
production bridge must preserve the original-deck `false` values in question
and prepared-answer packets. Three cards in a separate deck exercise cloze
answer extraction/comparison, known fields with empty values, and unknown-field
warning/marker removal. These are host-only generic fixtures; they do not add
note-type-specific behavior to the production bridge.

The recipe also checksum-verifies all seven unmodified APKGs present in pinned
Anki's public test corpus. A second host-only binary imports each through the
semantic Anki service into its own disposable collection. The production
bridge selects a queued deck, renders a question and prepared answer, and the
actual reviewer runtime inserts all fourteen sides into the same persistent
`#qa`. `media.apkg` additionally proves imported `foo.wav` becomes one typed
question AV tag. The APKG files are hashed before and after; logs contain only
structural lengths/hashes. No COCA or user deck exists in the repository, so
this gate does not claim either.

No global Node/npm installation is required. `tools/install_host_node.sh`
downloads Node 20.18.2 into ignored `out/`, validates the official archive
SHA-256 for the host OS/architecture, and `tools/install_host_jsdom.sh` installs
jsdom 24.1.3 from the source-controlled npm lockfile. These are host-test
oracles and are never copied into the Kindle package.

The recipe also starts the pinned Anki sync server on a Docker-local loopback
port with a scratch base directory and synthetic credentials. Two independent
disposable clients exercise full upload, full download, normal-sync deck-state
propagation, media-byte propagation/status and idle abort through the production
sync C ABI. The evidence and server log are scanned for the synthetic username,
password and derived hkey. This is a controlled protocol/lifecycle test; it
does not contact AnkiWeb.

The export audit requires every review and sync ABI symbol listed in
`bridge/required_exports.txt`; the source contract requires that list to match
both public bridge headers exactly. The trap stops the server, restores the
pinned checkout and removes every disposable directory. It never opens
`/mnt/us/anki_data`. Evidence is written to:

```text
out/host-anki/bridge-smoke.txt
out/host-anki/bridge-integration.txt
out/host-anki/apkg-integration.txt
out/host-anki/apkg-packets.json
out/host-anki/apkg-reviewer.txt
out/host-anki/node-install.txt
out/host-anki/jsdom-install.txt
out/host-anki/sync-integration.txt
out/host-anki/bridge-exports.txt
out/host-anki/bridge-dynamic.txt
out/host-anki/bridge-library.sha256
```

This is executable synthetic review/sync/ownership/ABI evidence plus fixed
upstream APKG structural evidence, not original COCA/user-deck, live AnkiWeb or
PW6 evidence. The Anki bridge workflow invokes the same canonical script
instead of embedding its own injection/build/test recipe.

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

The Docker package executor forwards the same diagnostic-only flag:

```sh
KANKI_ALLOW_DIRTY=1 bash tools/local_package_docker.sh
```

It defaults to `0`; omitting the flag keeps the canonical clean-checkout gate.

## Relationship to GitHub Actions

`tools/build_kindle_package.sh` is the build definition. `.github/workflows/package.yml` is only one executor and artifact uploader. The workflow must not carry a second copy of the compilation/package recipe.

This means a GitHub-hosted runner outage is **not** a reason to stop compilation work. A clean local canonical build can provide actionable compiler/package evidence and can serve as release-candidate build evidence when hosted Actions is unavailable, provided the remaining issue #11 gates and PW6 hardware acceptance are completed against the exact artifact.

Hosted CI should still be rerun when available as independent confirmation, but it is not allowed to redefine the build.

## Evidence to record

For every meaningful local build, record:

- exact commit SHA;
- confirmation that the root checkout was clean before build;
- host Mac/Linux model/architecture and OS;
- Docker/OrbStack/Colima engine and version;
- builder platform (`linux/amd64` by default);
- Rust version;
- `toolchain-info.txt`;
- `mathjax-info.txt` and `archive-info.txt`;
- ZIP SHA-256;
- package exported-symbol and GLIBC evidence files;
- manifest verification result;
- whether this is the first build or a repeated clean rebuild.

Where practical, perform a second clean rebuild before freezing a release candidate and compare package contents/manifest. Bit-for-bit reproducibility is a separate gate to establish rather than assume.

## Troubleshooting

If Docker reports an architecture warning on Apple Silicon, confirm that amd64 emulation is enabled and leave `KANKI_LOCAL_PLATFORM=linux/amd64`. Do not switch to an ARM64 builder unless a separately checksum-pinned ARM64-host KindleHF toolchain is introduced and documented.

If the build is interrupted, rerun the same command. Cargo and KindleHF downloads are cached. The builder restores the temporary `third_party/anki/rslib` bridge injection with a shell trap, so repeated builds must not accumulate source edits.

If the package script reports a pin mismatch, do not bypass it. Update the checkout/submodules to the commit documented by `docs/RESUME.md` and retry.
