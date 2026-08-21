# Canonical ordinary-source audit — 2026-08-22

## Result

**PASS** for source-input independence at audited branch head:

```text
bb2c3044e32a8e526532168ed296023f7b3c5dc5
```

This is a source/input audit only. It does not replace the pending full build from the final release head or exact-rootfs QEMU smoke.

## Files reviewed

```text
.github/workflows/kindle-anki-port.yml
kindle-anki-port/Makefile
kindle-anki-port/testenv/scripts/run-static-gates.sh
kindle-anki-port/testenv/scripts/run-armhf-gates.sh
kindle-anki-port/testenv/scripts/package-and-audit.sh
kindle-anki-port/tests/test_source_contract.py
```

## Findings

### Workflow project root

The workflow defines:

```text
PROJECT=${{ github.workspace }}/kindle-anki-port
```

All project-owned build and test inputs are then addressed through that ordinary directory. The only non-project source inputs are explicitly fetched/pinned external inputs:

- official Anki commit `e5a6fbe27fdd4d57d5f712191b4a753032e57853`;
- Rust 1.92.0;
- koxtoolchain 2025.05 / `arm-kindlehf-linux-gnueabihf`.

### Host gates

`make static-test` invokes `kindle-anki-port/testenv/scripts/run-static-gates.sh`, which consumes project-local `tools/`, `tests/`, `web/`, `scripts/`, `native/`, `core/` and `testenv/` paths. No archive restoration step is required.

### Official backend integration

The workflow fetches official Anki into `/tmp/anki` and invokes:

```text
$PROJECT/tools/inject_into_anki.py --project $PROJECT --anki /tmp/anki --skip-submodules
```

The injected semantic adapter therefore comes from the ordinary `kindle-anki-port/` tree.

### ARMHF build

`run-armhf-gates.sh` compiles the official Anki backend from `$ANKI` and compiles Kindle native programs from:

```text
$PROJECT/core
$PROJECT/native/app.c
$PROJECT/native/audio.c
$PROJECT/native/sync.c
```

It does not consume legacy root-level runtime sources, split archives, restored overlay directories or Ranki runtime code.

### Package assembly

`package-and-audit.sh` constructs the installer from:

```text
ARMHF outputs produced by run-armhf-gates.sh
$PROJECT/web
$PROJECT/scripts
$PROJECT/packaging
$PROJECT/LICENSE
```

The source archive emitted by the workflow is also explicitly:

```text
git archive <commit> kindle-anki-port
```

### Legacy staging

No reviewed build/package path references any of:

```text
part-*
kindle-anki-port-overlay
restore archive
rewrite-v1 runtime
LD_PRELOAD runtime
legacy repository-root src/scripts/tools as package inputs
```

`tests/test_source_contract.py` independently rejects several historical/card-specific runtime tokens and checks the semantic C-ABI/backend bridge boundary.

## Acceptance conclusion

The current workflow and package scripts resolve maintained project code entirely from ordinary `kindle-anki-port/` source plus explicitly pinned upstream/toolchain inputs. The old split-archive/overlay staging is not a build prerequisite.

The remaining release-provenance work is therefore execution, not source reconstruction: materialize the final branch head in the build VM, run the full host/backend/APKG/ARMHF/package sequence, then run exact-rootfs QEMU smoke once the private PW6 5.19.6 runtime bytes are available.
