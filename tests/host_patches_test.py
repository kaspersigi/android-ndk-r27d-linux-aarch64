#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Pre-build regression against the official reference; no LLVM build needed."""
import argparse
import hashlib
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PATCHER = runpy.run_path(str(ROOT / "scripts/apply-host-patches.py"))


class HostPatches(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="ndk-preflight-")
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name) / "ndk"
        PATCHER["prepare_reference"](REFERENCE, cls.root)
        PATCHER["patch_ndk"](cls.root)

    def test_exact_pinned_outputs(self):
        for line in (ROOT / "manifests/ndk-host-scripts.tsv").read_text().splitlines():
            if not line or line.startswith("#"):
                continue
            digest, relative = line.split()
            with self.subTest(path=relative):
                self.assertEqual(hashlib.sha256((self.root / relative).read_bytes()).hexdigest(), digest)

    def test_pyz_preserves_other_members_and_metadata(self):
        with zipfile.ZipFile(REFERENCE / "prebuilt/linux-x86_64/bin/ndkgdb.pyz") as before, \
                zipfile.ZipFile(self.root / PATCHER["PYZ"]) as after:
            self.assertEqual(before.namelist(), after.namelist())
            self.assertEqual(before.comment, after.comment)
            for old, new in zip(before.infolist(), after.infolist()):
                with self.subTest(member=old.filename):
                    for field in ("date_time", "compress_type", "external_attr", "internal_attr",
                                  "create_system", "extra", "comment"):
                        self.assertEqual(getattr(old, field), getattr(new, field))
                    if old.filename != "ndkgdb.py":
                        self.assertEqual(before.read(old), after.read(new))

    def test_entrypoint_contract(self):
        subprocess.run([sys.executable, "-B", str(ROOT / "tests/ndk_entrypoints_test.py"),
                        "--ndk", str(self.root)], check=True)

    def test_cmake_hook_host_scope_and_missing_sysroot(self):
        hook = self.root / "build/cmake/hooks/post/Android-Determine.cmake"
        for system, arch in (("Linux", "x86_64"), ("Darwin", "arm64"), ("Windows", "ARM64"),
                             ("Linux", "aarch64"), ("Linux", "arm64")):
            with self.subTest(system=system, arch=arch):
                probe = Path(self.temporary.name) / "probe.cmake"
                probe.write_text(
                    f'set(CMAKE_HOST_SYSTEM_NAME "{system}")\n'
                    f'set(CMAKE_HOST_SYSTEM_PROCESSOR "{arch}")\n'
                    f'set(CMAKE_ANDROID_NDK "{self.temporary.name}/missing")\n'
                    'set(CMAKE_ANDROID_NDK_TOOLCHAIN_HOST_TAG "unchanged")\n'
                    f'include("{hook}")\n'
                    'if(NOT CMAKE_ANDROID_NDK_TOOLCHAIN_HOST_TAG STREQUAL "unchanged")\n'
                    '  message(FATAL_ERROR "modified an unrelated host")\nendif()\n'
                )
                result = subprocess.run(["cmake", "-P", str(probe)], capture_output=True, text=True)
                if system == "Linux" and arch in ("aarch64", "arm64"):
                    self.assertNotEqual(result.returncode, 0)
                    self.assertIn("missing Linux AArch64 NDK unified sysroot", result.stderr)
                else:
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_shell_host_matrix(self):
        directory = Path(self.temporary.name) / "host-bin"
        directory.mkdir(exist_ok=True)
        uname = directory / "uname"
        for system, arch, expected in (("Linux", "aarch64", "linux-aarch64"),
                                       ("Linux", "arm64", "linux-aarch64"),
                                       ("Linux", "x86_64", "linux-x86_64"),
                                       ("Darwin", "arm64", "darwin-x86_64"),
                                       ("Darwin", "x86_64", "darwin-x86_64")):
            with self.subTest(system=system, arch=arch):
                uname.write_text(f'#!/bin/sh\ncase "$1" in -m) echo {arch};; -s) echo {system};; esac\n')
                uname.chmod(0o755)
                env = dict(os.environ, PATH=str(directory) + os.pathsep + os.environ["PATH"])
                result = subprocess.run(
                    ["bash", "-c", '. "$1"; printf "%s" "$HOST_TAG"', "probe",
                     str(self.root / "build/tools/ndk_bin_common.sh")],
                    env=env, text=True, capture_output=True, check=True)
                self.assertEqual(result.stdout, expected)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path)
    args, remaining = parser.parse_known_args()
    REFERENCE = args.reference.resolve(strict=True)
    unittest.main(argv=[sys.argv[0]] + remaining, verbosity=2)
