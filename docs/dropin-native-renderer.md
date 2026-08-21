# Direct replacement renderer package

This branch produces a complete `/mnt/us/extensions/ranki/` replacement and a matching `/mnt/us/documents/shortcut_ranki.sh`. It does not require KUAL.

## Renderer correction

The preload shim now intercepts the earliest direct `webkit_web_view_new()` call, enables Lab126 W3C CSS pixels globally, and replaces RAnki's `General.scale * screen_width / 600` request with the sequence observed in the Kindle Mesquite browser:

1. `webkit_web_view_set_useW3CStd_cssPixelsPerInch(1)`
2. `webkit_web_view_get_pixel_density()`
3. `webkit_web_view_set_full_content_zoom(view, 1)`
4. `webkit_web_view_set_zoom_level(view, density)`

The full-content step is mandatory. If any required Lab126 API is missing or the density is invalid, the shim falls back to full-content zoom at 1.0 rather than applying text-only density zoom.

The injected document records either `kanki-native-scale` or `kanki-scale-fallback` on the root element. `ranki.log` records a single `KANKI_SCALE` status line for the process.

## Direct-launch package

The existing RAnki release already contains a Kindle-library launcher named `shortcut_ranki.sh`. The complete replacement artifact therefore contains:

```text
ranki/                     complete extension directory
shortcut_ranki.sh          copy to /mnt/us/documents/
INSTALL.txt                replacement and rollback instructions
```

The shortcut continues to execute `/mnt/us/extensions/ranki/ranki.sh`, so the user launches the application in the same way as the original RAnki package. KUAL is not involved.

## Replacement safety

`/mnt/us/anki_data` remains outside the package and is not modified. For an in-place replacement, preserve the existing `/mnt/us/extensions/ranki/config.ini`, because it may contain the AnkiWeb key and collection path.
