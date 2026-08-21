#!/bin/bash
set -euo pipefail

ROOT=${KANKI_ROOT:-/work}
PACKAGE_ROOT=${KANKI_PACKAGE_ROOT:-$ROOT/out/local-kindle/package}
FIRMWARE_VERSION=5.19.6
FIRMWARE_URL=https://s3.amazonaws.com/firmwaredownloads/update_kindle_all_new_paperwhite_12th_5.19.6.bin
FIRMWARE_NAME=update_kindle_all_new_paperwhite_12th_5.19.6.bin
FIRMWARE_SIZE=412492749
FIRMWARE_SHA256=72445ffe3142991535902922a69969b913d4b27c58af4ceda1a3dc5ffadd143c
FIRMWARE_TARGET_OTA=4832160042
ROOTFS_BUILD=483216
ROOTFS_GZ_SHA256=d8c45cccf631e24dcc8556002cc5f37de6571a23729a8e5fb8adb7f6d938a698
ROOTFS_SHA256=b3dc1a4e9a73f103bb98537dfd4bfd16734296a8e10600292e1d1229b05c5cfa
TTS_SQSH_SHA256=0724e2fca5d8bba72681cc5a9d593c68a76f3b0b22a367e613dd01ffba22c15b
KINDLETOOL_COMMIT=4d559f6c5b3ebf7dd2d5cfb26c7fd9a601234eda

CACHE=$ROOT/out/firmware/pw6-$FIRMWARE_VERSION
TOOLS_CACHE=$ROOT/out/firmware-tools
FIRMWARE=$CACHE/$FIRMWARE_NAME
EXTRACTED=$CACHE/extracted
ROOTFS_IMAGE=$EXTRACTED/rootfs.img
ROOTFS_TREE=$CACHE/rootfs-tree
TTS_TREE=$CACHE/tts-squashfs
KINDLETOOL=$TOOLS_CACHE/kindletool-$KINDLETOOL_COMMIT
EXT=$PACKAGE_ROOT/extensions/kanki
CHROOT_PACKAGE=/mnt/us/extensions/kanki
CHROOT_REPORTS=/mnt/us/kanki_reports

PACKAGE_ELF=(
    libanki-kanki.so
    kanki-device
    kanki-sync
    kanki-diag
    kanki-raise
    kanki-audio
    kanki-gst-play
)
PACKAGE_EXECUTABLES=(
    kanki-device
    kanki-sync
    kanki-diag
    kanki-raise
    kanki-audio
    kanki-gst-play
)
TEMP_PATHS=()

fail() {
    echo "kanki-pw6-audit: $*" >&2
    exit 1
}

need() {
    command -v "$1" >/dev/null 2>&1 ||
        fail "missing required command in audit image: $1"
}

sha256() {
    sha256sum "$1" | awk '{print $1}'
}

require_hash() {
    local path=$1
    local expected=$2
    local label=$3
    test -f "$path" || fail "$label is missing: $path"
    test "$(sha256 "$path")" = "$expected" ||
        fail "$label checksum does not match the fixed PW6 baseline: $path"
}

register_temp() {
    case "$1" in
        "$CACHE"/.*|/tmp/kanki-pw6-chroot.*) TEMP_PATHS+=("$1") ;;
        *) fail "refusing unsafe temporary path: $1" ;;
    esac
}

cleanup() {
    local path
    for path in "${TEMP_PATHS[@]}"; do
        case "$path" in
            "$CACHE"/.*|/tmp/kanki-pw6-chroot.*) rm -rf -- "$path" ;;
        esac
    done
}
trap cleanup EXIT INT TERM

for command in awk chroot cp curl debugfs file find git grep gzip install make \
               mktemp mv python3 qemu-arm-static readelf sha256sum stat tar \
               unsquashfs; do
    need "$command"
done

case "$CACHE" in
    "$ROOT"/out/firmware/pw6-*) ;;
    *) fail "firmware cache must remain inside the repository out/ directory" ;;
esac
case "$PACKAGE_ROOT" in
    "$ROOT"/out/*) ;;
    *) fail "package input must remain inside the repository out/ directory" ;;
esac

cd "$ROOT"
test "$(git branch --show-current)" = rewrite-v1 ||
    fail "audit must run on rewrite-v1"
test -z "$(git status --porcelain --untracked-files=normal --ignore-submodules=dirty)" ||
    fail "repository must be clean before candidate evidence is generated"
test "$(git -C third_party/kindle-sdk/KindleTool rev-parse HEAD)" = "$KINDLETOOL_COMMIT" ||
    fail "fixed KindleTool submodule is not initialized at $KINDLETOOL_COMMIT"

mkdir -p "$CACHE" "$TOOLS_CACHE"

printf '%s\n' '== validate canonical package identity =='
test -d "$EXT" || fail "canonical package is missing; run bash tools/local_package_docker.sh"
test -f "$EXT/BUILD.json" || fail "canonical package BUILD.json is missing"
test -f "$EXT/MANIFEST.sha256" || fail "canonical package manifest is missing"
CANDIDATE=$(python3 - "$EXT/BUILD.json" <<'PY'
import json
import sys
from pathlib import Path

build = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
print(build["kanki_commit"])
PY
)
CURRENT=$(git rev-parse HEAD)
test "$CANDIDATE" = "$CURRENT" ||
    fail "package candidate $CANDIDATE does not match current HEAD $CURRENT"
EVIDENCE=$CACHE/evidence/$CANDIDATE
mkdir -p "$EVIDENCE"
(
    cd "$EXT"
    sha256sum --quiet -c MANIFEST.sha256
)
{
    printf 'candidate=%s\n' "$CANDIDATE"
    printf 'build_json_sha256=%s\n' "$(sha256 "$EXT/BUILD.json")"
    printf 'manifest_sha256=%s\n' "$(sha256 "$EXT/MANIFEST.sha256")"
    printf 'manifest_check=pass\n'
} > "$EVIDENCE/package-identity.txt"
cp "$EXT/BUILD.json" "$EVIDENCE/BUILD.json"

printf '%s\n' '== build fixed KindleTool audit dependency =='
if [ ! -x "$KINDLETOOL" ]; then
    KT_BUILD=$(mktemp -d "$CACHE/.kindletool-build.XXXXXX")
    register_temp "$KT_BUILD"
    git -C third_party/kindle-sdk/KindleTool archive "$KINDLETOOL_COMMIT" |
        tar -x -C "$KT_BUILD"
    SOURCE_DATE_EPOCH=$(git -C third_party/kindle-sdk/KindleTool show -s --format=%ct "$KINDLETOOL_COMMIT")
    (
        cd "$KT_BUILD"
        SOURCE_DATE_EPOCH="$SOURCE_DATE_EPOCH" \
        KT_NO_USERATHOST_TAG=1 \
        make CFLAGS='-O2 -mtune=generic -fno-omit-frame-pointer -pipe'
    )
    install -m 0755 "$KT_BUILD/KindleTool/Release/kindletool" "$KINDLETOOL"
fi

printf '%s\n' '== download and authenticate official PW6 firmware =='
if [ ! -f "$FIRMWARE" ] ||
   [ "$(stat -c %s "$FIRMWARE" 2>/dev/null || true)" != "$FIRMWARE_SIZE" ] ||
   [ "$(sha256 "$FIRMWARE" 2>/dev/null || true)" != "$FIRMWARE_SHA256" ]; then
    PART=$CACHE/.$FIRMWARE_NAME.partial
    register_temp "$PART"
    curl -fL --retry 4 --retry-all-errors --continue-at - \
        "$FIRMWARE_URL" -o "$PART"
    test "$(stat -c %s "$PART")" = "$FIRMWARE_SIZE" ||
        fail "downloaded firmware size is not $FIRMWARE_SIZE"
    require_hash "$PART" "$FIRMWARE_SHA256" "official PW6 firmware"
    mv -f "$PART" "$FIRMWARE"
fi
test "$(stat -c %s "$FIRMWARE")" = "$FIRMWARE_SIZE" ||
    fail "cached firmware size is not $FIRMWARE_SIZE"
require_hash "$FIRMWARE" "$FIRMWARE_SHA256" "official PW6 firmware"
"$KINDLETOOL" convert -i "$FIRMWARE" > "$EVIDENCE/firmware-info.txt" 2>&1
grep -Eq '^Bundle[[:space:]]+SP01 ' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware is not wrapped in the expected official SP01 envelope"
grep -Eq '^Cert number[[:space:]]+2$' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware does not use expected Amazon certificate 2"
grep -Eq '^Bundle[[:space:]]+FB03 ' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware payload is not FB03 Recovery V2"
grep -Eq '^Bundle Type[[:space:]]+Recovery V2$' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware payload type is not Recovery V2"
grep -Eq "^Target OTA[[:space:]]+$FIRMWARE_TARGET_OTA$" "$EVIDENCE/firmware-info.txt" ||
    fail "firmware target OTA is not $FIRMWARE_TARGET_OTA"
grep -Eq '^Platform[[:space:]]+Bellatrix4$' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware platform is not Bellatrix4"
grep -Eq '^Devices[[:space:]]+10$' "$EVIDENCE/firmware-info.txt" ||
    fail "firmware does not enumerate all 10 fixed PW6 variants"

printf '%s\n' '== extract and authenticate PW6 root filesystem =='
if [ ! -d "$EXTRACTED" ]; then
    EXTRACT_TMP=$(mktemp -d "$CACHE/.extracted.XXXXXX")
    register_temp "$EXTRACT_TMP"
    "$KINDLETOOL" extract "$FIRMWARE" "$EXTRACT_TMP"
    require_hash "$EXTRACT_TMP/rootfs.img.gz" "$ROOTFS_GZ_SHA256" "PW6 rootfs gzip"
    gzip -dc "$EXTRACT_TMP/rootfs.img.gz" > "$EXTRACT_TMP/rootfs.img"
    require_hash "$EXTRACT_TMP/rootfs.img" "$ROOTFS_SHA256" "PW6 rootfs image"
    mv "$EXTRACT_TMP" "$EXTRACTED"
fi
require_hash "$EXTRACTED/rootfs.img.gz" "$ROOTFS_GZ_SHA256" "PW6 rootfs gzip"
if [ ! -f "$ROOTFS_IMAGE" ]; then
    ROOTFS_TMP=$CACHE/.rootfs.img.partial
    register_temp "$ROOTFS_TMP"
    gzip -dc "$EXTRACTED/rootfs.img.gz" > "$ROOTFS_TMP"
    require_hash "$ROOTFS_TMP" "$ROOTFS_SHA256" "PW6 rootfs image"
    mv "$ROOTFS_TMP" "$ROOTFS_IMAGE"
fi
require_hash "$ROOTFS_IMAGE" "$ROOTFS_SHA256" "PW6 rootfs image"

if [ ! -d "$ROOTFS_TREE" ]; then
    TREE_TMP=$(mktemp -d "$CACHE/.rootfs-tree.XXXXXX")
    register_temp "$TREE_TMP"
    debugfs -R "rdump / $TREE_TMP" "$ROOTFS_IMAGE"
    test -f "$TREE_TMP/etc/prettyversion.txt" ||
        fail "debugfs did not extract a usable rootfs"
    mv "$TREE_TMP" "$ROOTFS_TREE"
fi
grep -Fq "Kindle $FIRMWARE_VERSION" "$ROOTFS_TREE/etc/prettyversion.txt" ||
    fail "rootfs pretty version does not match $FIRMWARE_VERSION"
grep -Fq "042-juno_1906_sangria_bellatrix4-$ROOTFS_BUILD" \
    "$ROOTFS_TREE/etc/version.txt" ||
    fail "rootfs system identity does not match the fixed PW6 candidate"
require_hash "$ROOTFS_TREE/usr/lib/tts.sqsh" "$TTS_SQSH_SHA256" "PW6 TTS squashfs"

if [ ! -d "$TTS_TREE" ]; then
    TTS_TMP=$(mktemp -d "$CACHE/.tts.XXXXXX")
    register_temp "$TTS_TMP"
    unsquashfs -no-xattrs -d "$TTS_TMP/root" "$ROOTFS_TREE/usr/lib/tts.sqsh"
    test -f "$TTS_TMP/root/libIvonaEInkAPI.so.1.0" ||
        fail "TTS squashfs lacks libIvonaEInkAPI.so.1.0"
    test -f "$TTS_TMP/root/libIvonaEInkCommon.so.1.0" ||
        fail "TTS squashfs lacks libIvonaEInkCommon.so.1.0"
    mv "$TTS_TMP/root" "$TTS_TREE"
fi
test -f "$TTS_TREE/libIvonaEInkAPI.so.1.0" ||
    fail "cached TTS tree lacks libIvonaEInkAPI.so.1.0"
test -f "$TTS_TREE/libIvonaEInkCommon.so.1.0" ||
    fail "cached TTS tree lacks libIvonaEInkCommon.so.1.0"

{
    printf 'firmware_version=%s\n' "$FIRMWARE_VERSION"
    printf 'firmware_url=%s\n' "$FIRMWARE_URL"
    printf 'firmware_size=%s\n' "$FIRMWARE_SIZE"
    printf 'firmware_sha256=%s\n' "$(sha256 "$FIRMWARE")"
    printf 'rootfs_gz_sha256=%s\n' "$(sha256 "$EXTRACTED/rootfs.img.gz")"
    printf 'rootfs_sha256=%s\n' "$(sha256 "$ROOTFS_IMAGE")"
    printf 'tts_sqsh_sha256=%s\n' "$(sha256 "$ROOTFS_TREE/usr/lib/tts.sqsh")"
    printf 'kindletool_commit=%s\n' "$KINDLETOOL_COMMIT"
    printf 'kindletool_sha256=%s\n' "$(sha256 "$KINDLETOOL")"
    printf 'qemu_arm_static_sha256=%s\n' "$(sha256 /usr/bin/qemu-arm-static)"
    cat "$ROOTFS_TREE/etc/prettyversion.txt"
    cat "$ROOTFS_TREE/etc/version.txt"
} > "$EVIDENCE/rootfs-identity.txt"

printf '%s\n' '== stage immutable rootfs clone and canonical package =='
CHROOT=$(mktemp -d /tmp/kanki-pw6-chroot.XXXXXX)
register_temp "$CHROOT"
cp -a "$ROOTFS_TREE/." "$CHROOT/"
mkdir -p "$CHROOT/opt/kanki-audit" "$CHROOT$CHROOT_PACKAGE" \
    "$CHROOT$CHROOT_REPORTS" "$CHROOT/usr/lib/tts" "$CHROOT/var/tmp"
install -m 0755 /usr/bin/qemu-arm-static "$CHROOT/usr/bin/qemu-arm-static"
for name in "${PACKAGE_ELF[@]}"; do
    install -m 0755 "$EXT/$name" "$CHROOT/opt/kanki-audit/$name"
done
cp -a "$EXT/." "$CHROOT$CHROOT_PACKAGE/"
cp -a "$TTS_TREE/." "$CHROOT/usr/lib/tts/"

printf '%s\n' '== execute packaged verifier under PW6 BusyBox =='
if ! env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/chroot "$CHROOT" /usr/bin/qemu-arm-static \
    /bin/sh "$CHROOT_PACKAGE/kanki-verify.sh" "$CHROOT_PACKAGE" \
    > "$EVIDENCE/package-verifier-pw6-busybox.txt" 2>&1; then
    cat "$EVIDENCE/package-verifier-pw6-busybox.txt" >&2
    fail "packaged install verifier failed under the PW6 BusyBox shell"
fi
grep -Fxq 'kanki-install-integrity=pass' \
    "$EVIDENCE/package-verifier-pw6-busybox.txt" ||
    fail "PW6 BusyBox verifier evidence lacks the success marker"

printf '%s\n' '== execute collection operation lock under PW6 flock/BusyBox =='
cat > "$CHROOT/opt/kanki-audit/operation-lock-probe.sh" <<'SH'
#!/bin/sh
set -eu

LOCK_ROOT=/var/tmp/kanki-operation-lock-probe
HELPER=/mnt/us/extensions/kanki/kanki-operation-lock.sh
rm -rf "$LOCK_ROOT"
mkdir "$LOCK_ROOT"
cp /mnt/us/extensions/kanki/.kanki.operation.lock \
    "$LOCK_ROOT/.kanki.operation.lock"

export KANKI_OPERATION_ROOT=$LOCK_ROOT
export KANKI_OPERATION_LOCK_FILE="$LOCK_ROOT/.kanki.operation.lock"
export KANKI_OPERATION_STATE_DIR="$LOCK_ROOT/.kanki.lock"
export KANKI_FLOCK=/usr/bin/flock
export KANKI_LOCK_HELPER=$HELPER

expect_busy() {
    if /bin/sh -c '
        exec 9>&-
        . "$KANKI_LOCK_HELPER"
        kanki_operation_lock_acquire sync
    '; then
        echo 'PW6 operation-lock probe: contender unexpectedly acquired' >&2
        exit 1
    else
        STATUS=$?
    fi
    test "$STATUS" -eq 74
}

/usr/bin/flock --version
. "$HELPER"
kanki_operation_lock_acquire launch
test "$(cat "$KANKI_OPERATION_STATE_DIR/pid")" = "$$"
test "$(cat "$KANKI_OPERATION_STATE_DIR/mode")" = launch
expect_busy

KANKI_EXPECTED_OWNER=$$
export KANKI_EXPECTED_OWNER
/bin/sh -c '
    . "$KANKI_LOCK_HELPER"
    kanki_operation_lock_validate_inherited "$KANKI_EXPECTED_OWNER" launch
'
echo 'inherited_launcher_handoff=pass'

# Closing or killing the wrapper cannot release the lock while a collection
# worker still holds the inherited open file description.
/bin/sleep 1 &
WORKER_PID=$!
exec 9>&-
KANKI_OPERATION_LOCK_HELD=0
expect_busy
wait "$WORKER_PID"

/bin/sh -c '
    exec 9>&-
    . "$KANKI_LOCK_HELPER"
    kanki_operation_lock_acquire sync
    kanki_operation_lock_cleanup
'
test ! -d "$KANKI_OPERATION_STATE_DIR"
echo 'worker_inherited_lock_lifetime=pass'
echo 'collection_operation_lock=pass'
SH
chmod 0755 "$CHROOT/opt/kanki-audit/operation-lock-probe.sh"
if ! env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/chroot "$CHROOT" /usr/bin/qemu-arm-static \
    /bin/sh /opt/kanki-audit/operation-lock-probe.sh \
    > "$EVIDENCE/operation-lock-pw6-busybox.txt" 2>&1; then
    cat "$EVIDENCE/operation-lock-pw6-busybox.txt" >&2
    fail "collection operation lock failed under PW6 flock/BusyBox"
fi
for expected in \
    inherited_launcher_handoff=pass \
    worker_inherited_lock_lifetime=pass \
    collection_operation_lock=pass; do
    grep -Fxq "$expected" "$EVIDENCE/operation-lock-pw6-busybox.txt" ||
        fail "PW6 operation-lock evidence lacks $expected"
done

printf '%s\n' '== execute privacy-redacted report under PW6 BusyBox =='
REPORT_SENTINEL=KANKI_PRIVATE_SENTINEL_DO_NOT_BUNDLE
REPORT_SAFE_LOG=KANKI_SAFE_LOG_MARKER
REPORT_SAFE_METRIC=KANKI_SAFE_METRIC_MARKER
printf '%s\n' \
    "$REPORT_SAFE_LOG startup=ready" \
    "password=$REPORT_SENTINEL" \
    "hkey=$REPORT_SENTINEL" \
    "endpoint=$REPORT_SENTINEL" \
    > "$CHROOT$CHROOT_PACKAGE/kanki.log"
printf 'hkey=%s\n' "$REPORT_SENTINEL" \
    > "$CHROOT$CHROOT_PACKAGE/config.ini"
mkdir "$CHROOT$CHROOT_PACKAGE/render-debug"
printf '%s innerWidth=1072 qaWidth=1072\n' "$REPORT_SAFE_METRIC" \
    > "$CHROOT$CHROOT_PACKAGE/render-debug/metrics.log"
printf '{"raw_note":"%s"}\n' "$REPORT_SENTINEL" \
    > "$CHROOT$CHROOT_PACKAGE/render-debug/card-0001.json"
printf '%s\n' "$REPORT_SENTINEL" \
    > "$CHROOT$CHROOT_PACKAGE/enable-render-capture"

if ! env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    /usr/sbin/chroot "$CHROOT" /usr/bin/qemu-arm-static \
    /bin/sh "$CHROOT_PACKAGE/kanki-report.sh" \
    > "$EVIDENCE/redacted-report-pw6-busybox.txt" 2>&1; then
    cat "$EVIDENCE/redacted-report-pw6-busybox.txt" >&2
    fail "redacted report failed under the PW6 BusyBox shell"
fi
grep -Fq "Kanki report created: $CHROOT_REPORTS/kanki-report-" \
    "$EVIDENCE/redacted-report-pw6-busybox.txt" ||
    fail "PW6 BusyBox report evidence lacks the published archive marker"

mapfile -t REPORT_ARCHIVES < <(
    find "$CHROOT$CHROOT_REPORTS" -mindepth 1 -maxdepth 1 \
        -type f -name 'kanki-report-*.tar.gz' -print
)
test "${#REPORT_ARCHIVES[@]}" -eq 1 ||
    fail "PW6 BusyBox report did not publish exactly one archive"
REPORT_ARCHIVE=${REPORT_ARCHIVES[0]}
test "$(stat -c %a "$CHROOT$CHROOT_REPORTS")" = 700 ||
    fail "PW6 BusyBox report output root is not private mode 0700"
test "$(stat -c %a "$REPORT_ARCHIVE")" = 600 ||
    fail "PW6 BusyBox report archive is not private mode 0600"
if find "$CHROOT$CHROOT_REPORTS" -mindepth 1 -maxdepth 1 \
    \( -type d -name 'kanki-report-*' -o -name '.kanki-report-*.partial' \) \
    -print | grep -q .; then
    fail "PW6 BusyBox report left a work tree or partial archive"
fi

REPORT_EXTRACT=$(mktemp -d "$CACHE/.report-extract.XXXXXX")
register_temp "$REPORT_EXTRACT"
tar -xzf "$REPORT_ARCHIVE" -C "$REPORT_EXTRACT"
mapfile -t REPORT_TREES < <(
    find "$REPORT_EXTRACT" -mindepth 1 -maxdepth 1 -type d \
        -name 'kanki-report-*' -print
)
test "${#REPORT_TREES[@]}" -eq 1 ||
    fail "PW6 BusyBox report archive lacks one bounded report root"
REPORT_TREE=${REPORT_TREES[0]}
test "$(stat -c %a "$REPORT_TREE")" = 700 ||
    fail "PW6 BusyBox report work tree was not private mode 0700"
for name in README.txt BUILD.json MANIFEST.sha256 INSTALL.md \
            renderer-metrics.log kanki.redacted.log system.txt integrity.txt; do
    test -f "$REPORT_TREE/$name" ||
        fail "PW6 BusyBox report archive lacks $name"
    test "$(stat -c %a "$REPORT_TREE/$name")" = 600 ||
        fail "PW6 BusyBox report member $name is not private mode 0600"
done
if grep -R -Fq "$REPORT_SENTINEL" "$REPORT_TREE"; then
    fail "PW6 BusyBox report archive leaked a synthetic private sentinel"
fi
grep -Fq "$REPORT_SAFE_LOG startup=ready" "$REPORT_TREE/kanki.redacted.log" ||
    fail "PW6 BusyBox report lost the non-private log control line"
grep -Fq "$REPORT_SAFE_METRIC" "$REPORT_TREE/renderer-metrics.log" ||
    fail "PW6 BusyBox report lost the privacy-safe renderer metric"
grep -Fxq 'kanki-install-integrity=pass' "$REPORT_TREE/integrity.txt" ||
    fail "PW6 BusyBox report did not record passing install integrity"
if find "$REPORT_TREE" -type f \
    \( -name config.ini -o -name 'card-*' -o -name enable-render-capture \) \
    -print | grep -q .; then
    fail "PW6 BusyBox report included config, raw capture or capture sentinel"
fi
{
    printf 'output_root_mode=%s\n' \
        "$(stat -c %a "$CHROOT$CHROOT_REPORTS")"
    printf 'archive_mode=%s\n' "$(stat -c %a "$REPORT_ARCHIVE")"
    printf 'report_tree_mode=%s\n' "$(stat -c %a "$REPORT_TREE")"
    printf 'report_member_mode=600\n'
    printf 'archive_sha256=%s\n' "$(sha256 "$REPORT_ARCHIVE")"
    printf 'private_sentinel_absent=pass\n'
    printf 'safe_log_control=pass\n'
    printf 'safe_renderer_metric=pass\n'
    printf 'raw_capture_excluded=pass\n'
    printf 'failure_staging_absent=pass\n'
} > "$EVIDENCE/redacted-report-privacy.txt"
tar -tzvf "$REPORT_ARCHIVE" > "$EVIDENCE/redacted-report-contents.txt"

printf '%s\n' '== verify ARMv7 hard-float ELF identity and symbol versions =='
: > "$EVIDENCE/elf-abi.txt"
for name in "${PACKAGE_ELF[@]}"; do
    file "$EXT/$name" | tee -a "$EVIDENCE/elf-abi.txt"
    file "$EXT/$name" | grep -Fq 'ELF 32-bit LSB' ||
        fail "$name is not ELF32 little-endian"
    readelf -h "$EXT/$name" | grep -Eq 'Machine:[[:space:]]+ARM' ||
        fail "$name is not an ARM ELF"
    readelf -A "$EXT/$name" | grep -Fq 'Tag_ABI_VFP_args: VFP registers' ||
        fail "$name is not hard-float EABI"
done
for name in "${PACKAGE_EXECUTABLES[@]}"; do
    readelf -l "$EXT/$name" | grep -Fq '/lib/ld-linux-armhf.so.3' ||
        fail "$name does not use the Kindle ARMHF interpreter"
done

python3 - "$ROOT" "$ROOTFS_TREE" "$EXT" "$EVIDENCE" "${PACKAGE_ELF[@]}" <<'PY'
import re
import subprocess
import sys
from pathlib import Path

root = Path(sys.argv[1])
rootfs = Path(sys.argv[2])
package = Path(sys.argv[3])
evidence = Path(sys.argv[4])
package_names = sys.argv[5:]


def dynamic_symbols(path: Path) -> set[str]:
    output = subprocess.run(
        ["readelf", "--dyn-syms", "--wide", str(path)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout
    symbols: set[str] = set()
    for line in output.splitlines():
        fields = line.split()
        if len(fields) >= 8 and fields[0].rstrip(":").isdigit():
            symbols.add(fields[7].split("@", 1)[0])
    return symbols


device = (root / "device/kanki_device.c").read_text(encoding="utf-8")
providers = {
    "gtk_lib": rootfs / "usr/lib/libgtk-x11-2.0.so.0",
    "webkit_lib": rootfs / "usr/lib/libwebkitgtk-1.0.so.0",
    "gobject_lib": rootfs / "usr/lib/libgobject-2.0.so.0",
}
lines: list[str] = []
for key, provider in providers.items():
    requested: list[tuple[str, str]] = []
    for line in device.splitlines():
        if f"app->{key}" not in line or "LOAD_" not in line:
            continue
        match = re.search(r'LOAD_(REQUIRED|OPTIONAL)\(.*"([^"]+)"\);', line)
        if match:
            requested.append((match.group(1).lower(), match.group(2)))
    available = dynamic_symbols(provider)
    missing = [symbol for _, symbol in requested if symbol not in available]
    required = sum(kind == "required" for kind, _ in requested)
    optional = sum(kind == "optional" for kind, _ in requested)
    lines.append(
        f"{key}: required={required} optional={optional} "
        f"available_requested={len(requested) - len(missing)} missing={len(missing)}"
    )
    if missing:
        raise SystemExit(f"{key} missing PW6 symbols: {', '.join(missing)}")

raise_source = (root / "device/kanki_raise.c").read_text(encoding="utf-8")
expected_x11 = {
    "XOpenDisplay",
    "XCloseDisplay",
    "XDefaultRootWindow",
    "XQueryTree",
    "XFetchName",
    "XFree",
    "XMapRaised",
    "XSetInputFocus",
    "XFlush",
}
x11_requested: list[str] = []
for source_line in raise_source.splitlines():
    if "LOAD_FN(" not in source_line:
        continue
    match = re.search(r'LOAD_FN\([^\"]*"([^"]+)"', source_line)
    if match:
        x11_requested.append(match.group(1))
if len(x11_requested) != len(expected_x11) or set(x11_requested) != expected_x11:
    raise SystemExit(
        "unexpected X11 source contract: " + ", ".join(x11_requested)
    )
x11_available = dynamic_symbols(rootfs / "usr/lib/libX11.so.6")
x11_missing = [symbol for symbol in x11_requested if symbol not in x11_available]
lines.append(
    f"x11: required={len(x11_requested)} "
    f"available_requested={len(x11_requested) - len(x11_missing)} missing={len(x11_missing)}"
)
if x11_missing:
    raise SystemExit(f"x11 missing PW6 symbols: {', '.join(x11_missing)}")
(evidence / "ui-symbols.txt").write_text("\n".join(lines) + "\n", encoding="utf-8")

version_pattern = re.compile(r"\b(?:GLIBC|GCC|LIBATOMIC)_[0-9][0-9.]*\b")


def versions(paths: list[Path]) -> set[str]:
    found: set[str] = set()
    for path in paths:
        output = subprocess.run(
            ["readelf", "--version-info", str(path)],
            check=True,
            text=True,
            stdout=subprocess.PIPE,
        ).stdout
        found.update(version_pattern.findall(output))
    return found


required_versions = versions([package / name for name in package_names])
provided_versions = versions(
    [
        rootfs / "lib/libc.so.6",
        rootfs / "lib/libgcc_s.so.1",
        rootfs / "usr/lib/libatomic.so.1",
    ]
)
missing_versions = sorted(required_versions - provided_versions)
(evidence / "required-symbol-versions.txt").write_text(
    "\n".join(sorted(required_versions)) + "\n", encoding="utf-8"
)
(evidence / "provided-symbol-versions.txt").write_text(
    "\n".join(sorted(provided_versions)) + "\n", encoding="utf-8"
)
if missing_versions:
    raise SystemExit(
        "PW6 runtime lacks required symbol versions: " + ", ".join(missing_versions)
    )
PY

printf '%s\n' '== resolve package and native runtime dependency closures =='
LOADER_EVIDENCE=$EVIDENCE/loader-resolution.txt
: > "$LOADER_EVIDENCE"
loader_list() {
    local label=$1
    local target=$2
    local output
    output=$(mktemp "$CACHE/.loader.XXXXXX")
    register_temp "$output"
    printf '\n[%s]\n' "$label" > "$output"
    if ! chroot "$CHROOT" /usr/bin/qemu-arm-static \
        /lib/ld-linux-armhf.so.3 \
        --library-path /opt/kanki-audit:/usr/lib/tts:/usr/lib:/lib \
        --list "$target" >> "$output" 2>&1; then
        cat "$output" >&2
        fail "PW6 loader failed to resolve $label"
    fi
    cat "$output" >> "$LOADER_EVIDENCE"
}

for name in "${PACKAGE_ELF[@]}"; do
    loader_list "package:$name" "/opt/kanki-audit/$name"
done
loader_list rootfs:gtk /usr/lib/libgtk-x11-2.0.so.0
loader_list rootfs:gobject /usr/lib/libgobject-2.0.so.0
loader_list rootfs:webkit /usr/lib/libwebkitgtk-1.0.so.0
loader_list rootfs:x11 /usr/lib/libX11.so.6
loader_list rootfs:gstreamer /usr/lib/libgstreamer-1.0.so.0
loader_list rootfs:mixersink /usr/lib/gstreamer-1.0/libgstmixersink.so.1.0
loader_list rootfs:ttssrc /usr/lib/gstreamer-1.0/libgstttssrc.so.1.0
if grep -Eqi 'not found|version .* not found|error loading shared library' "$LOADER_EVIDENCE"; then
    fail "PW6 loader evidence contains an unresolved runtime dependency"
fi

printf '%s\n' '== execute UI/backend and audio ABI probes under PW6 loader =='
if ! env -i PATH=/usr/bin:/bin:/usr/sbin:/sbin HOME=/var/tmp TMPDIR=/var/tmp \
    /usr/sbin/chroot "$CHROOT" /usr/bin/qemu-arm-static \
    /opt/kanki-audit/kanki-device \
    --backend /opt/kanki-audit/libanki-kanki.so --abi-probe \
    > "$EVIDENCE/ui-backend-probe.txt" 2>&1; then
    fail "kanki-device UI/backend ABI probe failed under the PW6 loader"
fi
for expected in \
    kanki_ui_abi=pass \
    kanki_backend_abi=pass \
    webkit_w3c_css_pixels=1 \
    webkit_pixel_density=1 \
    webkit_full_content_zoom=1 \
    webkit_zoom_level=1; do
    grep -Fxq "$expected" "$EVIDENCE/ui-backend-probe.txt" ||
        fail "PW6 UI/backend probe lacks $expected"
done

if ! env -i \
    PATH=/usr/bin:/bin:/usr/sbin:/sbin \
    HOME=/var/tmp \
    TMPDIR=/var/tmp \
    LD_LIBRARY_PATH=/usr/lib/tts:/usr/lib:/lib \
    GST_PLUGIN_PATH=/usr/lib/gstreamer-1.0 \
    GST_PLUGIN_SYSTEM_PATH=/usr/lib/gstreamer-1.0 \
    GST_REGISTRY=/var/tmp/kanki-gstreamer-registry.bin \
    GST_REGISTRY_FORK=no \
    GST_DEBUG_NO_COLOR=1 \
    /usr/sbin/chroot "$CHROOT" /usr/bin/qemu-arm-static \
    /opt/kanki-audit/kanki-gst-play --probe \
    > "$EVIDENCE/audio-probe.txt" 2>&1; then
    fail "kanki-gst-play probe failed under the PW6 loader"
fi
for expected in \
    build=native \
    gstreamer=loaded \
    filesrc=found \
    capsfilter=found \
    fdsrc=found \
    fakesrc=found \
    fakesink=found \
    mixersink=found \
    ttssrc=found \
    wavparse=not_found \
    audioconvert=found \
    audioresample=found; do
    grep -Fxq "$expected" "$EVIDENCE/audio-probe.txt" ||
        fail "PW6 audio probe lacks $expected"
done
grep -Fq 'gst-play: preloaded /usr/lib/tts/libIvonaEInkAPI.so.1.0' \
    "$EVIDENCE/audio-probe.txt" ||
    fail "PW6 audio probe did not preload the TTS runtime mount"
grep -Fq 'gst-play: preloaded /usr/lib/tts/libIvonaEInkCommon.so.1.0' \
    "$EVIDENCE/audio-probe.txt" ||
    fail "PW6 audio probe did not preload the TTS common runtime"

{
    printf 'pw6_rootfs_audit=pass\n'
    printf 'candidate=%s\n' "$CANDIDATE"
    printf 'firmware_version=%s\n' "$FIRMWARE_VERSION"
    printf 'firmware_sha256=%s\n' "$FIRMWARE_SHA256"
    printf 'firmware_target_ota=%s\n' "$FIRMWARE_TARGET_OTA"
    printf 'rootfs_build=%s\n' "$ROOTFS_BUILD"
    printf 'rootfs_sha256=%s\n' "$ROOTFS_SHA256"
    printf 'tts_sqsh_sha256=%s\n' "$TTS_SQSH_SHA256"
    printf 'package_manifest=pass\n'
    printf 'package_verifier_pw6_busybox=pass\n'
    printf 'collection_operation_lock_pw6_busybox=pass\n'
    printf 'redacted_report_pw6_busybox=pass\n'
    printf 'armv7_hard_float=pass\n'
    printf 'loader_resolution=pass\n'
    printf 'ui_backend_dlopen_dlsym=pass\n'
    printf 'lab126_css_pixel_symbols=pass\n'
    printf 'gstreamer_mixersink_ttssrc=pass\n'
    printf 'hardware_execution=not_run\n'
} > "$EVIDENCE/SUMMARY.txt"
(
    cd "$EVIDENCE"
    find . -maxdepth 1 -type f ! -name EVIDENCE.sha256 -print0 |
        sort -z |
        xargs -0 sha256sum > EVIDENCE.sha256
)

printf '\nPW6 rootfs audit: PASS\n'
printf 'candidate: %s\n' "$CANDIDATE"
printf 'evidence: %s\n' "$EVIDENCE"
printf 'hardware execution: not run\n'
