# ADR 0004: Normalize pinned Anki i18n generation deterministically

- Status: accepted
- Date: 2026-08-22

## Context

The fixed Anki 26.08.1 backend gathers Fluent resources with `HashMap` and
filesystem iteration in its build script. Two canonical builds of the same
Kanki commit produced equal-size ARMHF libraries whose first differing bytes
were reordered FTL text in `.rodata`. Reusing one Cargo target cache concealed
the problem because `anki_i18n` was not regenerated.

Changing archive timestamps cannot correct a backend binary whose build-time
source generation is nondeterministic. Moving the Anki gitlink would also
break the fixed-backend identity, while dropping translations would change
upstream behavior.

## Decision

Keep the Anki gitlink fixed. Before compiling, both canonical Anki build paths
authenticate upstream `rslib/i18n/gather.rs` by SHA-256 and replace only its
three build-time translation map aliases from `HashMap` to `BTreeMap`. The
normalizer authenticates its normalized output too. A trap restores the
submodule file on success, failure or interruption.

The normalization identifier and upstream/normalized source hashes are build
evidence and fields in the packaged `BUILD.json`. Full reproducibility evidence
must compare canonical builds using distinct empty Cargo target volumes so a
cached generated crate cannot substitute for regeneration.

## Boundaries

This is a source-build normalization, not a runtime patch layer. It does not
change the pinned Anki commit, translation keys or values, typed bridge,
scheduling, rendering, collection, media or sync semantics. It does not use
RAnki, `LD_PRELOAD`, binary rewriting or an undocumented post-checkout patch
sequence. The single canonical build recipe owns the operation.

If a future pinned Anki release makes its generator deterministic upstream,
remove this normalization only after two empty-target builds prove identical
and the new upstream source identity is recorded.

## Rejected alternatives

- Reusing one Cargo target volume for both builds: this tests cache reuse, not
  source reproducibility.
- Canonicalizing the final ELF or ZIP: that hides a changing backend input.
- Removing non-English FTL resources: that changes fixed-backend behavior.
- Advancing or dirtying the Anki submodule without a new backend decision: that
  loses the declared 26.08.1 source identity.
