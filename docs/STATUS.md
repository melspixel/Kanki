# Rewrite status

**Branch:** `rewrite-v1`  
**Release state:** architecture/bootstrap; not installable  
**Current closure:** none of Gates A–E is yet claimed complete

## Completed in the first clean commit

- pinned Anki, RAnki-reference and Kindle SDK sources;
- stable review-domain state machine;
- persistent Anki-style reviewer shell;
- deck-agnostic reviewer baseline;
- exact `cardN` body-class protocol;
- ES5 reviewer runtime;
- architecture, testing and handoff contracts;
- host and ARM cross-build CI definition.

## Next implementation order

1. typed Anki 26.08.1 adapter;
2. disposable-collection integration tests;
3. Kindle platform/UI implementation;
4. native CSS-pixel path and renderer probe;
5. source-owned audio service;
6. reproducible package and diagnostics;
7. parity corpus;
8. PW6 hardware acceptance.
