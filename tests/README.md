# Test contracts

Tests in this directory are cross-layer contracts for the rewrite. They are intended to prevent architecture regressions, not merely exercise one deck.

## Current groups

- `renderer_contract.test.cjs` — persistent reviewer lifecycle, card classes, script execution and AV controls.
- `css_compat.test.cjs` — generic old-WebKit compatibility behavior.
- `diagnostics_contract.test.cjs` — bounded/privacy-safe renderer diagnostics behavior.
- `navigation_contract.test.cjs` — reviewer navigation must preserve the persistent document.
- `bridge_source_contract.py` — semantic typed Anki bridge source invariants.
- `audio_source_contract.py` — native audio source/pipeline invariants.

## Rules

- Never add a fixture whose expected behavior depends on a named user deck as a special case.
- Representative real decks/APKGs may be used as compatibility fixtures, but the implementation must remain generic.
- Source-contract tests do not replace executable integration tests; issue #11 records which verification level has actually passed.
- A cleanup that moves files must keep these tests runnable from the canonical host gate.
