# RankiRefresh Diagnostic 1 provenance

## Git source identity

- Repository: `melspixel/Kanki`
- Destination branch/project: `kindle-anki-port` / `kindle-anki-port/RankiRefresh/`
- Diagnostic 1 CI merge commit: `f178e5e59e001bbf4964760d722fd6b9b10a28f1`
- Exact source tree: `8fb4d25339660e1b82a984f666b2e54d7a45defa`
- Renderer branch snapshot commit: `ba484b13e69d04f9dc85082a399b0bd544c256d5`
- Renderer CI run: `32402849169`
- Renderer artifact ID: `9419164966`
- Renderer artifact name: `kanki`

## Anki 26.08 backend identity

- Kanki backend branch commit: `b872a164c58aa5955975169944a647fdd678e99e`
- Backend CI run: `32399204271`
- Backend artifact ID: `9418086875`
- Backend artifact name: `anki-26.08-backend-kindlehf`
- Official Anki ref: `26.08`
- Official Anki commit used by the backend build: `666c2c64d4a1772c03948f5b667438da63ddaa76`

## Compiled package composition

`dist/Kanki-Anki26-diagnostics1.zip` is assembled from the retained renderer artifact plus the retained Anki 26.08 KindleHF backend artifact. The unpacked result is stored at `dist/unpacked/ranki/` as well, so GitHub contains the actual compiled runtime tree rather than only a pointer or manifest.

The final package contains the Ranki/Kanki launcher and runtime files, ARMHF/ARMEL Kanki helpers/shims, the upstream Ranki ARM binaries, the Kindle-native GStreamer helper, and `libanki-26.08-armhf.so` plus the backend redirect shim.

## Google Drive turnover/archive

Large build artifacts are also preserved under:

`GPT周转/RankiRefresh`

Folder ID: `1T6anthVF6GK516QL1TV6zerZOnpI-7wo`

Uploaded copies:

- `Kanki-Anki26-diagnostics1.zip` — Drive file ID `1FhTu8nMHS_5Y2hOcr3AqvqKwzorK1dCR`
- `Kanki-Anki26-diagnostics1.sha256` — Drive file ID `1Z8UILaI8qM6XBrCI-iztFA_X3DW4jjKi`
- `kanki-diagnostics1-renderer-artifact.zip` — Drive file ID `137r6iMqadeB2XYQucU9DVXTJWnFUSUwA`
- `anki26-kindlehf-backend-artifact.zip` — Drive file ID `1ZJp3Ghd6VpftDf1lQ-qjy68xIuBlcLk3`

Drive is used as a turnover/archive layer for large files. GitHub remains the canonical project tree and contains the complete source snapshot and compiled result after materialization.

## Reproducibility note

The upstream Kanki build workflow at this snapshot downloads the then-current upstream RAnki release binary and pins the additional helper inputs documented in `source/.github/workflows/build.yml`. The complete Kanki source structure itself is preserved under `source/`; third-party sources remain identified by their upstream repositories/refs exactly as the frozen workflow records them.
