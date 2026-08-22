#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import stat
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "testenv" / "scripts" / "run-qemu-smoke.sh"
ANKI_COMMIT = "2" * 40


def write_executable(path: Path, text: str) -> None:
    path.write_text(text, encoding="utf-8")
    path.chmod(path.stat().st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)


def remove_loose_object(path: Path, object_id: str) -> None:
    obj = path / ".git" / "objects" / object_id[:2] / object_id[2:]
    if not obj.is_file():
        raise AssertionError(f"expected loose fixture Git object: {obj}")
    obj.unlink()


class QemuProvenanceTest(unittest.TestCase):
    def make_fixture(self) -> tuple[tempfile.TemporaryDirectory[str], Path, Path, Path, Path, dict[str, str]]:
        td = tempfile.TemporaryDirectory()
        base = Path(td.name)
        project = base / "project"
        armhf = base / "armhf"
        rootfs = base / "rootfs"
        rootfs_image = base / "pw6-rootfs.img"
        tools = base / "tools"
        out = project / "build" / "qemu"
        for path in (
            project / "testenv" / "qemu",
            project / "testenv" / "scripts",
            project / "core",
            armhf,
            rootfs / "lib",
            tools,
        ):
            path.mkdir(parents=True, exist_ok=True)

        (project / ".gitignore").write_text("/build/\n", encoding="utf-8")
        (project / "upstream.lock.json").write_text(json.dumps({"commit": ANKI_COMMIT}) + "\n", encoding="utf-8")
        manifest = project / "testenv" / "qemu" / "pw6-5.19.6-rootfs-manifest.json"
        manifest.write_text('{"schema":1,"fixture":"canonical"}\n', encoding="utf-8")
        (project / "testenv" / "qemu" / "smoke.c").write_text("int main(void){return 0;}\n", encoding="utf-8")
        (project / "core" / "kap_core.h").write_text("/* fixture */\n", encoding="utf-8")
        write_executable(
            project / "testenv" / "scripts" / "verify-pw6-rootfs.py",
            """#!/usr/bin/env python3
import hashlib
import sys
if '--rootfs-image' not in sys.argv:
    raise SystemExit('missing --rootfs-image')
image = sys.argv[sys.argv.index('--rootfs-image') + 1]
digest = hashlib.sha256(open(image, 'rb').read()).hexdigest()
print(f'rootfs image sha256: PASS {digest}')
print('PW6 rootfs verification: PASS')
""",
        )
        (rootfs / "lib" / "ld-linux-armhf.so.3").write_bytes(b"loader")
        rootfs_image.write_bytes(b"canonical-rootfs-image-fixture\n")

        for name in ("kap-app", "kap-audio", "kap-sync", "libanki-kindle.so"):
            (armhf / name).write_bytes((name + "\n").encode())
        (armhf / "ARMHF-GATES.txt").write_text("ARMHF gates: PASS\n", encoding="utf-8")

        write_executable(
            tools / "arm-kindlehf-linux-gnueabihf-gcc",
            """#!/bin/sh
set -eu
out=
while [ "$#" -gt 0 ]; do
  if [ "$1" = -o ]; then out=$2; shift 2; continue; fi
  shift
done
[ -n "$out" ]
printf 'smoke fixture\\n' > "$out"
chmod +x "$out"
""",
        )
        debugfs = tools / "fake-debugfs"
        write_executable(
            debugfs,
            f"""#!/bin/sh
set -eu
[ "${{1:-}}" = -R ]
dest=${{2#rdump / }}
mkdir -p "$dest"
cp -R {str(rootfs)!r}/. "$dest"/
""",
        )
        qemu = tools / "fake-qemu"
        write_executable(
            qemu,
            """#!/bin/sh
if [ "${1:-}" = --version ]; then
  echo 'qemu-arm fixture 1.0'
  exit 0
fi
if [ -n "${QEMU_ARGS_LOG:-}" ]; then printf '%s\\n' "$*" >> "$QEMU_ARGS_LOG"; fi
case "$*" in
  *kap-qemu-smoke*) echo 'qemu backend smoke: ok' ;;
  *kap-audio*) echo 'kap-audio self-test: ok' ;;
  *kap-sync*) echo 'kap-sync self-test: ok' ;;
esac
""",
        )

        subprocess.run(["git", "init", "-q", str(project)], check=True)
        subprocess.run(["git", "-C", str(project), "config", "user.email", "fixture@example.invalid"], check=True)
        subprocess.run(["git", "-C", str(project), "config", "user.name", "fixture"], check=True)
        subprocess.run(["git", "-C", str(project), "add", "."], check=True)
        git_env = os.environ.copy()
        git_env.update({"GIT_AUTHOR_DATE": "2000-01-01T00:00:00Z", "GIT_COMMITTER_DATE": "2000-01-01T00:00:00Z"})
        subprocess.run(["git", "-C", str(project), "commit", "-qm", "fixture"], check=True, env=git_env)
        actual_head = subprocess.check_output(["git", "-C", str(project), "rev-parse", "HEAD"], text=True).strip()
        (armhf / "BUILD-PROVENANCE.txt").write_text(
            f"source_commit={actual_head}\nanki_commit={ANKI_COMMIT}\n",
            encoding="utf-8",
        )

        run_env = os.environ.copy()
        run_env.update(
            {
                "PROJECT": str(project),
                "ARMHF": str(armhf),
                "ROOTFS": str(rootfs),
                "ROOTFS_IMAGE": str(rootfs_image),
                "TOOLCHAIN_BIN": str(tools),
                "QEMU_ARM": str(qemu),
                "DEBUGFS": str(debugfs),
                "QEMU_ARGS_LOG": str(base / "qemu-args.log"),
                "OUT": str(out),
                "BUILD_COMMIT": actual_head,
            }
        )
        return td, project, armhf, rootfs, out, run_env

    def run_gate(self, env: dict[str, str]) -> subprocess.CompletedProcess[str]:
        return subprocess.run(["bash", str(SCRIPT)], env=env, text=True, capture_output=True)

    def test_matching_release_provenance_passes_and_is_recorded(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 0, result.stderr + result.stdout)
        self.assertEqual((out / "QEMU-SMOKE.txt").read_text(), "QEMU smoke: PASS\n")
        self.assertTrue((out / "input-rootfs-verification.txt").is_file())
        verification = (out / "rootfs-verification.txt").read_text()
        self.assertIn("PW6 rootfs verification: PASS", verification)
        image_hash = hashlib.sha256(Path(env["ROOTFS_IMAGE"]).read_bytes()).hexdigest()
        self.assertIn(f"rootfs image sha256: PASS {image_hash}", verification)
        provenance = (out / "QEMU-PROVENANCE.txt").read_text()
        self.assertIn(f"source_commit={env['BUILD_COMMIT']}\n", provenance)
        self.assertIn(f"anki_commit={ANKI_COMMIT}\n", provenance)
        self.assertIn("rootfs_manifest_id=pw6-5.19.6-rootfs-manifest.json\n", provenance)
        self.assertIn("rootfs_manifest_sha256=", provenance)
        self.assertIn("rootfs_input_verified=true\n", provenance)
        self.assertIn("rootfs_verified=true\n", provenance)
        self.assertIn("rootfs_runtime_source=verified-image-rdump\n", provenance)
        self.assertIn(f"rootfs_image_sha256={image_hash}\n", provenance)
        self.assertNotIn(str(rootfs), provenance)
        self.assertNotIn(env["ROOTFS_IMAGE"], provenance)
        qemu_args = Path(env["QEMU_ARGS_LOG"]).read_text(encoding="utf-8")
        self.assertNotIn(f"-L {rootfs}", qemu_args)
        self.assertIn("kap-qemu-rootfs.", qemu_args)
        for name in ("libanki-kindle.so", "kap-app", "kap-audio", "kap-sync"):
            self.assertIn(f"{name}_sha256=", provenance)

    def test_failed_dynamic_rerun_invalidates_old_pass(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        first = self.run_gate(env)
        self.assertEqual(first.returncode, 0, first.stderr + first.stdout)
        Path(env["DEBUGFS"]).write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
        second = self.run_gate(env)
        self.assertEqual(second.returncode, 66, second.stderr + second.stdout)
        self.assertFalse((out / "QEMU-SMOKE.txt").exists())
        self.assertFalse((out / "QEMU-PROVENANCE.txt").exists())

    def test_missing_rootfs_image_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        env.pop("ROOTFS_IMAGE")
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("ROOTFS_IMAGE=<checksum-verified PW6 rootfs image> is required", result.stderr)

    def test_nonfile_rootfs_image_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        env["ROOTFS_IMAGE"] = str(Path(td.name) / "missing.img")
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("PW6 rootfs image is missing or not a regular file", result.stderr)

    def test_stale_armhf_source_commit_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        (armhf / "BUILD-PROVENANCE.txt").write_text(
            f"source_commit={'3' * 40}\nanki_commit={ANKI_COMMIT}\n", encoding="utf-8"
        )
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("ARMHF source_commit mismatch", result.stderr)

    def test_wrong_armhf_anki_commit_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        (armhf / "BUILD-PROVENANCE.txt").write_text(
            f"source_commit={env['BUILD_COMMIT']}\nanki_commit={'4' * 40}\n", encoding="utf-8"
        )
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("ARMHF anki_commit mismatch", result.stderr)

    def test_nonpassing_armhf_gate_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        (armhf / "ARMHF-GATES.txt").write_text("ARMHF gates: FAIL\n", encoding="utf-8")
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("does not record PASS", result.stderr)

    def test_alternate_manifest_bytes_are_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        alternate = Path(td.name) / "alternate.json"
        alternate.write_text('{"schema":1,"fixture":"not-canonical"}\n', encoding="utf-8")
        env["ROOTFS_MANIFEST"] = str(alternate)
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("does not match the canonical PW6 5.19.6 manifest", result.stderr)

    def test_dirty_project_tree_is_rejected(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        (project / "testenv" / "qemu" / "smoke.c").write_text("int main(void){return 1;}\n", encoding="utf-8")
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("project source tree is dirty", result.stderr)

    def test_project_head_commit_object_must_exist(self) -> None:
        td, project, armhf, rootfs, out, env = self.make_fixture()
        self.addCleanup(td.cleanup)
        remove_loose_object(project, env["BUILD_COMMIT"])
        result = self.run_gate(env)
        self.assertEqual(result.returncode, 66, result.stderr + result.stdout)
        self.assertIn("resolvable Git HEAD commit", result.stderr)
        self.assertFalse((out / "QEMU-SMOKE.txt").exists())


if __name__ == "__main__":
    unittest.main()
