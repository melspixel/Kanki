# Kanki documentation index

Use this page to avoid treating overlapping project documents as separate projects.

## Start here

- `CODEX_HANDOFF.md` — zero-context operational handoff for a local coding agent/maintainer; includes repository cleanup plan and local-build sequence.
- `STATUS.md` — current implemented/verified/blocked state. This is the answer to “what is happening now?”.
- `RESUME.md` — compact zero-context route through invariants, source map and
  entry commands; mutable status and detailed contracts link to their owner
  documents instead of being copied here.

## Design and parity

- `ARCHITECTURE.md` — system boundaries and high-level design.
- `ANKI_DESKTOP_PARITY.md` — behavior audit against pinned Anki 26.08.1 desktop reviewer.
- `adr/` — architecture decisions and rationale.

## Build, test and release

- `LOCAL_BUILD.md` — local Docker/Linux build path that bypasses GitHub-hosted Actions.
- `TESTING.md` — verification gates and evidence rules.
- `INSTALL.md` — device installation/rollback contract.
- `HANDOFF.md` — permanent maintainer/release operating contract.

## External closure records

- PR #10 — active rewrite integration PR, kept Draft until closure.
- Issue #11 — authoritative verification checklist. A checked box means evidence exists for the candidate; it does not merely mean source code exists.

## Document ownership rule

Avoid repeating the same state in every document:

- current state belongs in `STATUS.md`;
- first-run/takeover procedure belongs in `CODEX_HANDOFF.md`;
- architecture belongs in `ARCHITECTURE.md`/ADRs;
- local build belongs in `LOCAL_BUILD.md`;
- verification belongs in `TESTING.md` + issue #11;
- desktop semantics belong in `ANKI_DESKTOP_PARITY.md`;
- long-term maintainer/release policy belongs in `HANDOFF.md`.

When information moves to its owner document, replace duplicate paragraphs elsewhere with a link rather than maintaining multiple copies.
