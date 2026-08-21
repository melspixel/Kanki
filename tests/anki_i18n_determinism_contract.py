#!/usr/bin/env python3
"""Keep build-time Anki translation embedding deterministic and bounded."""

import importlib.util
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
NORMALIZER_PATH = ROOT / "tools/normalize_anki_i18n.py"
SPEC = importlib.util.spec_from_file_location("normalize_anki_i18n", NORMALIZER_PATH)
if SPEC is None or SPEC.loader is None:
    raise SystemExit("Anki i18n determinism contract: unable to load normalizer")
NORMALIZER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(NORMALIZER)

UPSTREAM = ROOT / "third_party/anki/rslib/i18n/gather.rs"
source = UPSTREAM.read_bytes()
normalized = NORMALIZER.normalized_bytes(source)
if NORMALIZER.sha256(source) != NORMALIZER.UPSTREAM_SHA256:
    raise SystemExit("Anki i18n determinism contract: upstream source identity drifted")
if normalized == source:
    raise SystemExit("Anki i18n determinism contract: normalization changed nothing")

normalized_text = normalized.decode("utf-8")
if "HashMap" in normalized_text:
    raise SystemExit("Anki i18n determinism contract: randomized map remains")
for alias in ["TranslationsByRepo", "TranslationsByFile", "TranslationsByLang"]:
    if f"pub type {alias} = BTreeMap" not in normalized_text:
        raise SystemExit(f"Anki i18n determinism contract: {alias} is not ordered")

for script_name in ["build_kindle_package.sh", "run_anki_bridge_host.sh"]:
    script = (ROOT / "tools" / script_name).read_text(encoding="utf-8")
    for required in [
        "tools/normalize_anki_i18n.py",
        "rslib/i18n/gather.rs",
        "KANKI_ANKI_I18N_NORMALIZATION",
    ]:
        if required not in script:
            raise SystemExit(
                f"Anki i18n determinism contract: {script_name} lacks {required}"
            )

print("Anki i18n determinism contract: pass strategy=btree-map-v1")
