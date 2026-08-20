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

css = Path(sys.argv[1]).read_text(encoding='utf-8')
js = Path(sys.argv[2]).read_text(encoding='utf-8')

print('#ifndef KANKI_EMBEDDED_ASSETS_H')
print('#define KANKI_EMBEDDED_ASSETS_H')
print('static const char KANKI_REVIEWER_CSS[] =')
print(c_string(css) + ';')
print('static const char KANKI_COMPAT_JS[] =')
print(c_string(js) + ';')
print('#endif')
