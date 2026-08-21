#!/usr/bin/env python3
"""Make pinned Anki's build-time FTL map iteration deterministic."""

from __future__ import annotations

import hashlib
import sys
from pathlib import Path


UPSTREAM_SHA256 = "0844f9f54d95b1d6008a80226cc75829d1dc638f0388f231272d5ba88d8defb8"
NORMALIZED_SHA256 = "bd0d82698a6a56a095063eee822001a101be55566971493cb4a7552d5600a50c"
NORMALIZATION_ID = "btree-map-v1"
REPLACEMENTS = {
    "use std::collections::HashMap;": "use std::collections::BTreeMap;",
    "pub type TranslationsByRepo = HashMap<String, String>;":
        "pub type TranslationsByRepo = BTreeMap<String, String>;",
    "pub type TranslationsByFile = HashMap<String, TranslationsByRepo>;":
        "pub type TranslationsByFile = BTreeMap<String, TranslationsByRepo>;",
    "pub type TranslationsByLang = HashMap<String, TranslationsByFile>;":
        "pub type TranslationsByLang = BTreeMap<String, TranslationsByFile>;",
}


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def normalized_bytes(source: bytes) -> bytes:
    actual = sha256(source)
    if actual != UPSTREAM_SHA256:
        raise ValueError(
            "pinned Anki i18n source does not match the authenticated input: "
            f"expected {UPSTREAM_SHA256}, got {actual}"
        )

    text = source.decode("utf-8")
    for original, replacement in REPLACEMENTS.items():
        count = text.count(original)
        if count != 1:
            raise ValueError(
                f"expected one pinned Anki i18n fragment, found {count}: {original}"
            )
        text = text.replace(original, replacement, 1)
    normalized = text.encode("utf-8")
    actual_normalized = sha256(normalized)
    if actual_normalized != NORMALIZED_SHA256:
        raise ValueError(
            "normalized Anki i18n source identity drifted: "
            f"expected {NORMALIZED_SHA256}, got {actual_normalized}"
        )
    return normalized


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: normalize_anki_i18n.py PATH_TO_GATHER_RS")
    path = Path(sys.argv[1])
    source = path.read_bytes()
    try:
        normalized = normalized_bytes(source)
    except ValueError as error:
        raise SystemExit(f"kanki-anki-i18n: {error}") from error
    path.write_bytes(normalized)
    print(f"KANKI_ANKI_I18N_NORMALIZATION={NORMALIZATION_ID}")
    print(f"KANKI_ANKI_I18N_UPSTREAM_SHA256={sha256(source)}")
    print(f"KANKI_ANKI_I18N_NORMALIZED_SHA256={NORMALIZED_SHA256}")


if __name__ == "__main__":
    main()
