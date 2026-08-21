#!/usr/bin/env python3
"""Inject the Kindle Anki semantic port into an exact official Anki checkout.

The injector deliberately makes only four source changes:

1. add ``rslib/src/kap_port.rs`` containing the named external C ABI;
2. add ``rslib/src/services/kap_bridge.rs`` inside the generated-services
   privacy boundary;
3. declare both modules at stable anchors; and
4. request an rlib + cdylib build from rslib.

It is idempotent and refuses an unexpected upstream commit.
"""
from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


class InjectionError(RuntimeError):
    pass


def copy_if_changed(source: Path, target: Path) -> None:
    data = source.read_bytes()
    if target.is_file() and target.read_bytes() == data:
        return
    target.write_bytes(data)


def write_if_changed(path: Path, text: str) -> None:
    if path.is_file() and path.read_text(encoding="utf-8") == text:
        return
    path.write_text(text, encoding="utf-8")


def replace_once(path: Path, anchor: str, replacement: str) -> None:
    text = path.read_text(encoding="utf-8")
    if replacement in text:
        return
    if anchor not in text:
        raise InjectionError(f"stable anchor not found in {path}: {anchor!r}")
    path.write_text(text.replace(anchor, replacement, 1), encoding="utf-8")


def verify_checkout(anki: Path, expected: str) -> None:
    git_dir = anki / ".git"
    if not git_dir.exists():
        marker = anki / ".kap-upstream-commit"
        if marker.is_file() and marker.read_text(encoding="utf-8").strip() == expected:
            return
        raise InjectionError(
            "Anki checkout has no .git metadata and no matching "
            ".kap-upstream-commit marker"
        )
    actual = subprocess.check_output(
        ["git", "-C", str(anki), "rev-parse", "HEAD"], text=True
    ).strip()
    if actual != expected:
        raise InjectionError(f"Anki checkout mismatch: expected {expected}, got {actual}")


def ensure_translation_submodules(anki: Path) -> None:
    required = [anki / "ftl" / "core-repo" / "core", anki / "ftl" / "qt-repo" / "desktop"]
    if all(path.is_dir() for path in required):
        return
    if not (anki / ".git").exists():
        missing = ", ".join(str(path) for path in required if not path.is_dir())
        raise InjectionError(f"translation inputs missing from source bundle: {missing}")
    subprocess.run(
        [
            "git",
            "-C",
            str(anki),
            "submodule",
            "update",
            "--init",
            "--recursive",
            "--depth",
            "1",
        ],
        check=True,
    )
    if not all(path.is_dir() for path in required):
        raise InjectionError("Anki translation submodules did not initialize correctly")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path, required=True)
    parser.add_argument("--anki", type=Path, required=True)
    parser.add_argument(
        "--skip-submodules",
        action="store_true",
        help="use only when an already-complete source bundle is supplied",
    )
    args = parser.parse_args()

    project = args.project.resolve()
    anki = args.anki.resolve()
    lock = json.loads((project / "upstream.lock.json").read_text(encoding="utf-8"))
    expected = lock["commit"]
    verify_checkout(anki, expected)
    if not args.skip_submodules:
        ensure_translation_submodules(anki)

    port_source = project / "core" / "src" / "port.rs"
    bridge_source = project / "core" / "src" / "services_bridge.rs"
    if not port_source.is_file() or not bridge_source.is_file():
        raise InjectionError("semantic port or services bridge source is missing")

    port_target = anki / "rslib" / "src" / "kap_port.rs"
    bridge_target = anki / "rslib" / "src" / "services" / "kap_bridge.rs"
    bridge_target.parent.mkdir(parents=True, exist_ok=True)
    copy_if_changed(port_source, port_target)
    copy_if_changed(bridge_source, bridge_target)

    replace_once(
        anki / "rslib" / "src" / "lib.rs",
        "pub mod version;",
        "pub mod version;\npub mod kap_port;",
    )
    replace_once(
        anki / "rslib" / "src" / "services.rs",
        'include!(concat!(env!("OUT_DIR"), "/backend.rs"));',
        'include!(concat!(env!("OUT_DIR"), "/backend.rs"));\n\npub(crate) mod kap_bridge;',
    )

    cargo = anki / "rslib" / "Cargo.toml"
    cargo_text = cargo.read_text(encoding="utf-8")
    desired = '[lib]\ncrate-type = ["rlib", "cdylib"]'
    if "crate-type" not in cargo_text:
        cargo.write_text(cargo_text.rstrip() + "\n\n" + desired + "\n", encoding="utf-8")
    elif desired not in cargo_text:
        raise InjectionError("rslib already defines an unexpected crate-type")

    write_if_changed(anki / ".kap-upstream-commit", expected + "\n")
    print(f"Injected Kindle Anki semantic ABI into {anki}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, subprocess.CalledProcessError, InjectionError) as exc:
        raise SystemExit(f"injection failed: {exc}") from exc
