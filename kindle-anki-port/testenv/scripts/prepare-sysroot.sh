#!/bin/sh
set -eu
ROOTFS=${1:?usage: prepare-sysroot.sh ROOTFS EXPECTED_TREE_SHA256 OUTPUT_MANIFEST}
EXPECTED=${2:?}
MANIFEST=${3:?}
[ -d "$ROOTFS" ] || {
    echo "rootfs directory not found: $ROOTFS" >&2
    exit 2
}
LOADER="$ROOTFS/lib/ld-linux-armhf.so.3"
if [ ! -e "$LOADER" ] && [ ! -L "$LOADER" ]; then
    echo "rootfs lacks /lib/ld-linux-armhf.so.3" >&2
    exit 4
fi
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT HUP INT TERM
ACTUAL=$(python3 - "$ROOTFS" "$TMP" <<'PY'
import hashlib
import json
import os
import stat
import sys
from pathlib import Path

root = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2])
records = []
for path in sorted(root.rglob("*"), key=lambda item: item.relative_to(root).as_posix()):
    rel = path.relative_to(root).as_posix()
    st = path.lstat()
    record = {"mode": format(stat.S_IMODE(st.st_mode), "04o"), "path": rel}
    if stat.S_ISREG(st.st_mode):
        digest = hashlib.sha256()
        with path.open("rb") as stream:
            for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                digest.update(chunk)
        record.update(type="file", sha256=digest.hexdigest())
    elif stat.S_ISDIR(st.st_mode):
        record["type"] = "dir"
    elif stat.S_ISLNK(st.st_mode):
        record.update(type="symlink", target=os.readlink(path))
    elif stat.S_ISCHR(st.st_mode):
        record.update(type="char", major=os.major(st.st_rdev), minor=os.minor(st.st_rdev))
    elif stat.S_ISBLK(st.st_mode):
        record.update(type="block", major=os.major(st.st_rdev), minor=os.minor(st.st_rdev))
    elif stat.S_ISFIFO(st.st_mode):
        record["type"] = "fifo"
    elif stat.S_ISSOCK(st.st_mode):
        record["type"] = "socket"
    else:
        raise SystemExit(f"unsupported rootfs entry type: {rel}")
    records.append(record)
payload = json.dumps(
    {"algorithm": "kap-rootfs-tree-v1", "entries": records},
    ensure_ascii=False,
    separators=(",", ":"),
    sort_keys=True,
).encode("utf-8")
out.write_bytes(payload)
print(hashlib.sha256(payload).hexdigest())
PY
)
[ "$ACTUAL" = "$EXPECTED" ] || {
    echo "rootfs tree hash mismatch: expected $EXPECTED, got $ACTUAL" >&2
    exit 3
}
python3 - "$ROOTFS" "$ACTUAL" "$MANIFEST" <<'PY'
import json
import os
import sys
from pathlib import Path

rootfs, digest, output = sys.argv[1:]
data = {
    "schema": 2,
    "rootfs": str(Path(rootfs).resolve()),
    "tree_manifest_algorithm": "kap-rootfs-tree-v1",
    "tree_manifest_sha256": digest,
    "manifest_sha256": digest,
    "dynamic_linker": "/lib/ld-linux-armhf.so.3",
}
path = Path(output)
path.parent.mkdir(parents=True, exist_ok=True)
tmp = path.with_name(path.name + f".tmp.{os.getpid()}")
try:
    tmp.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    tmp.replace(path)
finally:
    try:
        tmp.unlink()
    except FileNotFoundError:
        pass
PY
