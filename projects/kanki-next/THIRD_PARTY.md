# Third-party inputs and redistribution policy

## RAnki

- Project: `crazy-electron/ranki`
- Pinned commit and release hashes: `upstream.lock`
- RAnki source is used as an audited behavioral reference and, during transition builds, as an upstream package input.
- Preserve its license notices when redistributing derived packages that contain upstream binaries.

## Anki

- Target backend: Anki 26.08 `rslib`
- The backend adapter must preserve Anki's applicable AGPL licensing and notices.

## Kindle firmware and source bundles

Amazon firmware/rootfs files and proprietary libraries are not committed, packaged, or redistributed by this subproject. CI retains only derived text inventories, hashes, ABI metadata, and call-site summaries.

## koxtoolchain / Kindle tooling

The CI cross-build downloads a pinned KindleHF koxtoolchain release. Its version is recorded in the workflow and build report.
