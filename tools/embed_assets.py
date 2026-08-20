#!/usr/bin/env python3
from pathlib import Path
import sys


def c_string(text: str) -> str:
    lines = []
    for line in text.splitlines(True):
        escaped = (
            line.replace('\\', '\\\\')
            .replace('"', '\\"')
            .replace('\t', '\\t')
            .replace('\r', '\\r')
            .replace('\n', '\\n')
        )
        lines.append(f'"{escaped}"')
    return '\n'.join(lines) if lines else '""'


if len(sys.argv) != 3:
    raise SystemExit('usage: embed_assets.py CSS JS')

css_path = Path(sys.argv[1])
js_path = Path(sys.argv[2])
css = css_path.read_text(encoding='utf-8')

# Keep the layers separately testable in source, then embed them in the order
# they must register their DOMContentLoaded hooks:
#   1) adaptive CSS/viewport preprocessing
#   2) mature Anki/audio compatibility layer
#   3) diagnostics, so its delayed snapshots observe the final DOM/layout
js_parts = []
adaptive_path = js_path.with_name('anki_adaptive_v2.js')
if adaptive_path.exists():
    js_parts.append(adaptive_path.read_text(encoding='utf-8'))
js_parts.append(js_path.read_text(encoding='utf-8'))
diagnostics_path = js_path.with_name('render_diagnostics.js')
if diagnostics_path.exists():
    js_parts.append(diagnostics_path.read_text(encoding='utf-8'))
js = '\n\n'.join(js_parts)

print('#ifndef KANKI_EMBEDDED_ASSETS_H')
print('#define KANKI_EMBEDDED_ASSETS_H')
print('static const char KANKI_REVIEWER_CSS[] =')
print(c_string(css) + ';')
print('static const char KANKI_COMPAT_JS[] =')
print(c_string(js) + ';')
print('#endif')
