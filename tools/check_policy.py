#!/usr/bin/env python3
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

renderer_assets = [
    ROOT / "assets/reviewer/reviewer.css",
    ROOT / "assets/reviewer/reviewer.js",
    ROOT / "assets/reviewer/css_compat.js",
    ROOT / "assets/reviewer/css_runtime.js",
    ROOT / "assets/reviewer/mathjax_runtime.js",
    ROOT / "assets/reviewer/diagnostics.js",
    ROOT / "assets/device/reviewer-shell.html",
]
renderer_rs = (ROOT / "crates/kanki-renderer/src/lib.rs").read_text(encoding="utf-8")
production_renderer_rs = renderer_rs.split("#[cfg(test)]", 1)[0]
text = (
    "\n".join(path.read_text(encoding="utf-8") for path in renderer_assets)
    + "\n"
    + production_renderer_rs
).lower()

errors: list[str] = []

# A generic reviewer must never accumulate one-deck fixes. If a deck needs a
# selector here, the compatibility boundary is wrong and must be redesigned.
forbidden_deck_tokens = [
    "coca-english",
    "dictionary-logo",
    ".pos-badge",
    ".word {",
    "merriam-webster",
]
for item in forbidden_deck_tokens:
    if item in text:
        errors.append(f"deck-specific token in generic renderer: {item}")

# The rewrite uses Kindle/Lab126 CSS pixels rather than re-creating the legacy
# 420px/media-query patch stack.
forbidden_layout_tokens = ["logical_viewport_px", "media_rewritten", "9999px"]
for item in forbidden_layout_tokens:
    if item in text:
        errors.append(f"legacy viewport/media rewrite token in renderer: {item}")
if re.search(r"(?i)(viewport|logical|breakpoint)[^\n]{0,80}420px", text):
    errors.append("hard-coded 420px logical viewport/breakpoint is forbidden")

css = (ROOT / "assets/reviewer/reviewer.css").read_text(encoding="utf-8")
if re.search(r"(?m)^\s*svg\s*\{", css):
    errors.append("generic SVG sizing rule is forbidden")
if re.search(r"(?m)^\s*img\s*\{[^}]*\b(width|height)\s*:", css, re.S):
    errors.append("generic fixed image sizing rule is forbidden")

shell = (ROOT / "assets/device/reviewer-shell.html").read_text(encoding="utf-8")
if 'id="qa"' not in shell:
    errors.append("persistent #qa root is missing from device reviewer shell")
for required in [
    "css_compat.js",
    "css_runtime.js",
    "MathJax.js?config=TeX-AMS_SVG-full",
    "mathjax_runtime.js",
    "diagnostics.js",
    "reviewer.js",
]:
    if required not in shell:
        errors.append(f"device reviewer shell does not load required runtime: {required}")

# Keep the host fixture aligned with the persistent reviewer contract as well.
host_reviewer = (ROOT / "assets/reviewer/reviewer.html").read_text(encoding="utf-8")
if 'id="qa"' not in host_reviewer:
    errors.append("persistent #qa root is missing from host reviewer fixture")

# Default renderer diagnostics are metadata-only. Raw source is explicit opt-in
# and bounded; the privacy-safe runtime must not scrape element text.
diagnostics = (ROOT / "assets/reviewer/diagnostics.js").read_text(encoding="utf-8")
if "textContent" in diagnostics or "innerText" in diagnostics:
    errors.append("privacy-safe renderer diagnostics must not scrape element text")
for required in ["RAW_RENDER_LIMIT = 12", "METRIC_RENDER_LIMIT = 200", "ELEMENT_LIMIT = 40"]:
    if required not in diagnostics:
        errors.append(f"renderer diagnostic bound missing: {required}")
if "rawCaptureEnabled" not in diagnostics:
    errors.append("raw renderer capture must remain an explicit runtime policy")

launch = (ROOT / "scripts/kanki-launch.sh").read_text(encoding="utf-8")
for required in ["render-debug", "enable-render-capture", "kanki-diag", "MANIFEST.sha256"]:
    if required not in launch:
        errors.append(f"launcher observability/integrity contract missing: {required}")

# Release reproducibility: KindleHF is checksum pinned and no workflow may
# silently float to a new 'latest' cross toolchain.
toolchain = (ROOT / "tools/install_kindlehf_toolchain.sh").read_text(encoding="utf-8")
if "KOX_VERSION=2026.08" not in toolchain:
    errors.append("KindleHF koxtoolchain release is not pinned")
if "8cc7dfbd71abd78f9e947d6b2e20670288a4402edc7b07176bca791f7eaf87d0" not in toolchain:
    errors.append("KindleHF koxtoolchain checksum is not pinned")

# Formula rendering is a source-owned, checksum-pinned part of the persistent
# reviewer. It must not silently float to another npm release or disappear
# from the canonical Kindle package recipe.
mathjax_installer = (ROOT / "tools/install_mathjax.sh").read_text(encoding="utf-8")
if "VERSION=2.7.9" not in mathjax_installer:
    errors.append("MathJax renderer release is not pinned")
if "7131e739848edc14aa661a5516995866b81a477fab8b039d7cc324930e71f786" not in mathjax_installer:
    errors.append("MathJax renderer checksum is not pinned")
package_recipe = (ROOT / "tools/build_kindle_package.sh").read_text(encoding="utf-8")
for required in [
    "sh tools/install_mathjax.sh",
    "assets/vendor/mathjax-$MATHJAX_VERSION",
    '"mathjax_version": "$MATHJAX_VERSION"',
    '"mathjax_sha256": "$MATHJAX_SHA256"',
]:
    if required not in package_recipe:
        errors.append(f"canonical package recipe lacks MathJax identity/runtime: {required}")
for required in [
    'BUILD_EPOCH=$(git show -s --format=%ct "$BUILD_COMMIT")',
    "python3 tools/create_reproducible_zip.py",
    '"source_date_epoch": $BUILD_EPOCH',
]:
    if required not in package_recipe:
        errors.append(f"canonical package recipe lacks deterministic archive input: {required}")
for workflow in (ROOT / ".github/workflows").glob("*.yml"):
    workflow_text = workflow.read_text(encoding="utf-8")
    if "releases/latest/download/kindlehf" in workflow_text:
        errors.append(f"floating KindleHF toolchain URL in {workflow.relative_to(ROOT)}")

# The host Anki bridge recipe is a repository script that can run locally or
# in CI. The workflow may install runner prerequisites and upload evidence, but
# must not grow a second copy of bridge injection/build/smoke logic.
anki_bridge_workflow = (ROOT / ".github/workflows/anki-bridge.yml").read_text(
    encoding="utf-8"
)
if "bash tools/run_anki_bridge_host.sh" not in anki_bridge_workflow:
    errors.append("Anki bridge workflow does not call the canonical host recipe")
for duplicated in [
    "cp bridge/anki_bridge.rs",
    "cargo build -p anki --release --features rustls",
    "bridge/smoke.c -Ibridge",
]:
    if duplicated in anki_bridge_workflow:
        errors.append(f"Anki bridge workflow duplicates canonical logic: {duplicated}")

if errors:
    print("\n".join(errors), file=sys.stderr)
    raise SystemExit(1)
print("renderer/reproducibility policy: pass")
