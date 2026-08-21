# Handoff — direct RAnki replacement

## Completed

- Replaced the global `0.90–1.25` zoom clamp with Kindle's native CSS-pixel and full-content-zoom path.
- Added an early `webkit_web_view_new()` interception to set the global Lab126 CSS-pixel mode before the first normal reviewer view.
- Kept the generic HTML/CSS/ES5 compatibility and audio layers.
- Added explicit native/fallback renderer markers and log records.
- Confirmed the deliverable must include the complete `ranki/` directory and the Kindle-library `shortcut_ranki.sh`; KUAL is not part of the installation path.

## Device acceptance

1. Preserve the current `/mnt/us/extensions/ranki/config.ini`.
2. Replace the contents of `/mnt/us/extensions/ranki/` with the new package, restoring the preserved `config.ini` afterward if necessary.
3. Replace `/mnt/us/documents/shortcut_ranki.sh`.
4. Launch from the Kindle library exactly as before.
5. Test a short card, an image-heavy card, and a long dictionary card on both sides.
6. Return `ranki.log`, `system-fingerprint.txt`, and the newest `render-debug/render-*-meta.txt` files.

Expected log marker on the PW6 native path:

```text
KANKI_SCALE|native-css-pixels|full-content-zoom
```

A fallback marker means the real device runtime does not match the firmware oracle or the inferred Lab126 function contract. Do not compensate by changing global card fonts before examining the device report.

## Next code milestone

After native-scale acceptance, move the persistent `#qa` reviewer work from `projects/kanki-next/` into the production application and replace RAnki's question/answer page reloads. Backend and scheduler behavior should remain unchanged until that renderer migration is independently validated.
