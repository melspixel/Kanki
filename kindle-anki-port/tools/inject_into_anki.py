#!/usr/bin/env python3
"""Inject the Kindle Anki semantic port into an exact official Anki checkout.

The injector deliberately makes only four source changes:

1. add ``rslib/src/kap_port.rs`` containing the named external C ABI;
2. add ``rslib/src/services/kap_bridge.rs`` inside the generated-services
   privacy boundary;
3. declare both modules at stable anchors; and
4. request an rlib + cdylib build from rslib.

It is idempotent, refuses an unexpected upstream commit, and verifies that a
Git checkout differs from the pinned Anki commit only by this deterministic
overlay. That prevents unrelated dirty Anki source from entering host/ARMHF
release evidence while still allowing the maintained bridge injection itself.
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
        ["git", "-C", str(anki), "rev-parse", "--verify", "HEAD^{commit}"],
        text=True,
        stderr=subprocess.DEVNULL,
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


def expected_replace(text: str, anchor: str, replacement: str, path: str) -> str:
    if replacement in text:
        if text.count(replacement) != 1:
            raise InjectionError(f"deterministic overlay appears multiple times in upstream {path}")
        return text
    if text.count(anchor) != 1:
        raise InjectionError(f"stable anchor count is not exactly one in upstream {path}: {anchor!r}")
    return text.replace(anchor, replacement, 1)


def git_show(anki: Path, relative: str) -> bytes:
    try:
        return subprocess.check_output(
            ["git", "-C", str(anki), "show", f"HEAD:{relative}"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError as exc:
        raise InjectionError(f"unable to read pinned upstream file from HEAD: {relative}") from exc


def expected_overlay(project: Path, anki: Path, expected: str) -> dict[str, bytes]:
    git_checkout = (anki / ".git").exists()

    def base_text(relative: str) -> str:
        if git_checkout:
            data = git_show(anki, relative)
        else:
            data = (anki / relative).read_bytes()
        return data.decode("utf-8")

    lib_relative = "rslib/src/lib.rs"
    services_relative = "rslib/src/services.rs"
    cargo_relative = "rslib/Cargo.toml"
    lib_text = expected_replace(
        base_text(lib_relative),
        "pub mod version;",
        "pub mod version;\npub mod kap_port;",
        lib_relative,
    )
    services_text = expected_replace(
        base_text(services_relative),
        'include!(concat!(env!("OUT_DIR"), "/backend.rs"));',
        'include!(concat!(env!("OUT_DIR"), "/backend.rs"));\n\npub(crate) mod kap_bridge;',
        services_relative,
    )
    cargo_text = base_text(cargo_relative)
    desired = '[lib]\ncrate-type = ["rlib", "cdylib"]'
    if desired in cargo_text:
        if cargo_text.count(desired) != 1:
            raise InjectionError("deterministic rslib crate-type appears multiple times upstream")
        expected_cargo = cargo_text
    elif "crate-type" not in cargo_text:
        expected_cargo = cargo_text.rstrip() + "\n\n" + desired + "\n"
    else:
        raise InjectionError("rslib already defines an unexpected crate-type")

    return {
        "rslib/src/kap_port.rs": (project / "core/src/port.rs").read_bytes(),
        "rslib/src/services/kap_bridge.rs": (project / "core/src/services_bridge.rs").read_bytes(),
        lib_relative: lib_text.encode("utf-8"),
        services_relative: services_text.encode("utf-8"),
        cargo_relative: expected_cargo.encode("utf-8"),
        ".kap-upstream-commit": (expected + "\n").encode("utf-8"),
    }


def git_paths(anki: Path, *args: str) -> set[str]:
    data = subprocess.check_output(["git", "-C", str(anki), *args])
    return {
        item.decode("utf-8", "surrogateescape")
        for item in data.split(b"\0")
        if item
    }


def verify_injected_overlay(project: Path, anki: Path, expected: str) -> None:
    overlay = expected_overlay(project, anki, expected)
    for relative, expected_bytes in overlay.items():
        path = anki / relative
        if not path.is_file():
            raise InjectionError(f"deterministic Anki overlay file is missing: {relative}")
        if path.read_bytes() != expected_bytes:
            raise InjectionError(f"Anki overlay bytes differ from pinned HEAD + project source: {relative}")

    if not (anki / ".git").exists():
        return

    expected_dirty: set[str] = set()
    for relative, expected_bytes in overlay.items():
        probe = subprocess.run(
            ["git", "-C", str(anki), "cat-file", "-e", f"HEAD:{relative}"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if probe.returncode != 0 or git_show(anki, relative) != expected_bytes:
            expected_dirty.add(relative)

    actual_dirty = set()
    actual_dirty |= git_paths(
        anki,
        "diff",
        "--name-only",
        "-z",
        "--no-ext-diff",
        "--ignore-submodules=none",
        "HEAD",
        "--",
    )
    actual_dirty |= git_paths(
        anki,
        "diff",
        "--cached",
        "--name-only",
        "-z",
        "--no-ext-diff",
        "--ignore-submodules=none",
        "HEAD",
        "--",
    )
    actual_dirty |= git_paths(anki, "ls-files", "--others", "--exclude-standard", "-z")
    if actual_dirty != expected_dirty:
        unexpected = sorted(actual_dirty - expected_dirty)
        missing = sorted(expected_dirty - actual_dirty)
        details = []
        if unexpected:
            details.append("unexpected=" + ",".join(unexpected))
        if missing:
            details.append("missing=" + ",".join(missing))
        raise InjectionError(
            "Anki checkout modifications do not match deterministic Kindle overlay"
            + (": " + "; ".join(details) if details else "")
        )


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
    verify_injected_overlay(project, anki, expected)
    print(f"Injected and verified Kindle Anki semantic ABI into {anki}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, UnicodeError, subprocess.CalledProcessError, InjectionError) as exc:
        raise SystemExit(f"injection failed: {exc}") from exc
