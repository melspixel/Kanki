# Independence boundary

This project is authored independently from `rewrite-v1`, RAnki and every
prior Kindle card-template patching experiment.

## Forbidden dependencies

- No source imports, submodules, copied implementation files, runtime binaries
  or install paths from `rewrite-v1`.
- No RAnki executable, Vala code, preload shim, deck-name check, note-type
  check, field-name heuristic or card-specific CSS patch.
- No compatibility behavior selected by vocabulary product or card content.

## Permitted inputs

- The pinned official Ankitects Anki source tree is the behavioral/backend
  source of truth.
- Kindle system ABI documentation and open-source Kindle tooling are platform
  references only.
- Third-party libraries are pinned and license-audited.

The automated policy gate rejects prohibited names and runtime paths from the
shipped source/package, while allowing this explanatory document itself.
