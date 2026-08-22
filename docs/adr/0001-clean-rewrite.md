# ADR 0001: Replace binary patching with a source-owned client

- Status: accepted
- Date: 2026-08-21

## Context

The previous experiment combined an upstream RAnki release with preload shims, a redirected Anki backend, CSS/media-query rewriting and external audio helpers. Mixed-version installs occurred, the launcher's state was not observable, and a viewport heuristic plus unconstrained SVG produced catastrophic layouts.

## Decision

Build a new client from source. Use the official Anki Rust backend through typed APIs. Keep one persistent reviewer document. Implement the Kindle platform explicitly against an audited rootfs and Lab126 WebKit capabilities. Treat RAnki as a behavior/reference source only.

## Consequences

The initial rewrite is more work than another patch, but component ownership, tests, upgrade boundaries and handoff become explicit. Existing `anki_data` remains the migration boundary; the old executable is not part of the new package.
