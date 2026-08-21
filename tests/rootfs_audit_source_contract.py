#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEVICE = (ROOT / "device/kanki_device.c").read_text(encoding="utf-8")
AUDIT = (ROOT / "tools/audit_pw6_rootfs.sh").read_text(encoding="utf-8")
WRAPPER = (ROOT / "tools/local_pw6_rootfs_audit.sh").read_text(encoding="utf-8")
DOCKERFILE = (ROOT / "tools/pw6-rootfs-audit.Dockerfile").read_text(
    encoding="utf-8"
)
HOST_GATES = (ROOT / "tools/run_host_gates.sh").read_text(encoding="utf-8")
PACKAGE = (ROOT / "tools/build_kindle_package.sh").read_text(encoding="utf-8")


def require(text: str, fragment: str, message: str) -> None:
    if fragment not in text:
        raise SystemExit(message)


def forbid(text: str, fragment: str, message: str) -> None:
    if fragment in text:
        raise SystemExit(message)


# The device-side check must exercise the actual dynamic loader and semantic
# backend exports, while stopping before assets, collection, GTK init, or a
# window are created.
for fragment in [
    "--abi-probe",
    "static int load_backend_api",
    "if (!load_backend_api(&app, backend_path))",
    'printf("kanki_ui_abi=pass',
    'printf("kanki_backend_abi=pass',
    "webkit_w3c_css_pixels",
    "webkit_pixel_density",
    "webkit_full_content_zoom",
    "webkit_zoom_level",
]:
    require(DEVICE, fragment, f"device ABI probe contract is missing: {fragment}")

probe = DEVICE.index("if (abi_probe)")
if not DEVICE.index("if (!load_ui(&app))") < probe < DEVICE.index(
    "app.deck_html = read_file"
):
    raise SystemExit("device ABI probe must run after UI dlopen and before UI assets")
if DEVICE.index("app->core = app->backend.core_new") < DEVICE.index(
    "static int load_backend(App"
):
    raise SystemExit("backend API loader must not instantiate Anki core")

# The firmware baseline is immutable and tied to Amazon's exact PW6 recovery
# image. Both compressed and extracted rootfs content are authenticated.
for fragment in [
    "FIRMWARE_VERSION=5.19.6",
    "update_kindle_all_new_paperwhite_12th_5.19.6.bin",
    "FIRMWARE_SIZE=412492749",
    "72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c",
    "FIRMWARE_TARGET_OTA=4832160042",
    "ROOTFS_BUILD=483216",
    "042-juno_1906_sangria_bellatrix4-$ROOTFS_BUILD",
    "d8c45cccf631e24dcc8556002cc5f37de6571a23729a8e5fb8adb7f6d938a698",
    "b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa",
    "0724e2fca5d8bba72681cc5a9d593c68a76f3b0b22a367e613dd01ffba22c15b",
    "4d559f6c5b3ebf7dd2d5cfb26c7fd9a601234eda",
]:
    require(AUDIT, fragment, f"fixed PW6 rootfs identity is missing: {fragment}")
forbid(
    AUDIT,
    "042-juno_1906_sangria_bellatrix4-$FIRMWARE_TARGET_OTA",
    "full target OTA must not be confused with the shorter rootfs build id",
)

# The observed ttssrc dependency lives in the firmware's tts.sqsh runtime
# mount. The audit must model that mount instead of patching the helper.
for fragment in [
    "unsquashfs",
    "usr/lib/tts.sqsh",
    'cp -a "$TTS_TREE/." "$CHROOT/usr/lib/tts/"',
    "libIvonaEInkAPI.so.1.0",
    "libIvonaEInkCommon.so.1.0",
    "mixersink=found",
    "ttssrc=found",
    "wavparse=not_found",
]:
    require(AUDIT, fragment, f"PW6 audio/rootfs audit is missing: {fragment}")

for fragment in [
    "Tag_ABI_VFP_args: VFP registers",
    "/lib/ld-linux-armhf.so.3",
    "required-symbol-versions.txt",
    "loader-resolution.txt",
    "--backend /opt/kanki-audit/libanki-kanki.so --abi-probe",
    "hardware_execution=not_run",
]:
    require(AUDIT, fragment, f"PW6 ABI evidence is missing: {fragment}")

forbidden_audit_paths = [
    "/mnt/us/anki_data",
    "/mnt/us/extensions/ranki",
    "LD_PRELOAD",
    "--privileged",
]
for fragment in forbidden_audit_paths:
    forbid(AUDIT, fragment, f"rootfs audit contains forbidden runtime mutation: {fragment}")

require(
    WRAPPER,
    "bash tools/audit_pw6_rootfs.sh",
    "local PW6 wrapper must call the canonical rootfs audit",
)
require(
    WRAPPER,
    "git -C third_party/kindle-sdk submodule update --init KindleTool",
    "local PW6 wrapper must initialize only the fixed KindleTool dependency",
)
require(
    WRAPPER,
    '    tools\n',
    "PW6 audit Docker build must use the small tools/ context",
)
for package in [
    "e2fsprogs",
    "libarchive-dev",
    "nettle-dev",
    "qemu-user-static",
    "squashfs-tools",
]:
    require(DOCKERFILE, package, f"PW6 audit image lacks container dependency: {package}")

require(
    HOST_GATES,
    "python3 tests/rootfs_audit_source_contract.py",
    "host gates must run the PW6 rootfs source contract",
)
require(
    PACKAGE,
    'builder": "tools/build_kindle_package.sh"',
    "canonical package identity must still name the sole package recipe",
)
forbid(
    PACKAGE,
    "audit_pw6_rootfs.sh",
    "canonical packaging must not embed or invoke the proprietary firmware audit",
)

print("PW6 rootfs audit source contract: pass")
