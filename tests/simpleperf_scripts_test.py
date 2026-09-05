#!/usr/bin/env python3
"""Test the packaged helpers on simulated hosts, without loading foreign ELF."""

import argparse
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

parser = argparse.ArgumentParser()
parser.add_argument("--ndk", required=True, type=Path)
args, remaining = parser.parse_known_args()
sys.path.insert(0, str(args.ndk.resolve() / "simpleperf"))
import simpleperf_utils as utils


class HostPathsTest(unittest.TestCase):
    def test_host_matrix(self):
        for system, machine, bits, directory, host_tag, library in (
            ("linux", "aarch64", 64, "linux/aarch64", "linux-aarch64", "libsimpleperf_report.so"),
            ("linux", "arm64", 64, "linux/aarch64", "linux-aarch64", "libsimpleperf_report.so"),
            ("linux", "x86_64", 64, "linux/x86_64", "linux-x86_64", "libsimpleperf_report.so"),
            ("linux", "i686", 32, "linux/x86", "linux-x86_64", "libsimpleperf_report.so"),
            ("win32", "ARM64", 64, "windows/x86_64", "windows-x86_64", "libsimpleperf_report.dll"),
            ("win32", "AMD64", 64, "windows/x86_64", "windows-x86_64", "libsimpleperf_report.dll"),
            ("darwin", "arm64", 64, "darwin/x86_64", "darwin-x86_64", "libsimpleperf_report.dylib"),
            ("darwin", "x86_64", 64, "darwin/x86_64", "darwin-x86_64", "libsimpleperf_report.dylib"),
        ):
            with self.subTest(system=system, machine=machine), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                expected = root / "bin" / directory / library
                expected.parent.mkdir(parents=True)
                expected.touch()
                with patch.object(utils.sys, "platform", system), \
                        patch.object(utils.sys, "maxsize", 2 ** (bits - 1) - 1), \
                        patch.object(utils.host_platform, "machine", return_value=machine), \
                        patch.object(utils, "get_script_dir", return_value=str(root)):
                    self.assertEqual(Path(utils.get_host_binary_path("libsimpleperf_report.so")), expected)
                    self.assertEqual(utils.get_ndk_host_tag(utils.get_platform()), host_tag)
                    for name in ("llvm-objdump", "llvm-readelf", "llvm-symbolizer", "llvm-strip"):
                        relative = utils.ToolFinder.EXPECTED_TOOLS[name]["path_in_ndk"](utils.get_platform())
                        self.assertEqual(relative, "toolchains/llvm/prebuilt/{}/bin/{}".format(host_tag, name))
                    _, relative = utils.ToolFinder._get_binutils_path_in_ndk("objdump", "arm64", utils.get_platform())
                    self.assertIn("/{}/bin/aarch64-linux-android-objdump".format(host_tag), relative)

    def test_arm64_missing_native_library_does_not_fall_back_to_x86(self):
        with tempfile.TemporaryDirectory() as tmp:
            old = Path(tmp) / "bin/linux/x86_64/libsimpleperf_report.so"
            old.parent.mkdir(parents=True)
            old.touch()
            with patch.object(utils.sys, "platform", "linux"), \
                    patch.object(utils.host_platform, "machine", return_value="aarch64"), \
                    patch.object(utils, "get_script_dir", return_value=tmp):
                with self.assertRaisesRegex(Exception, "linux/aarch64/libsimpleperf_report.so"):
                    utils.get_host_binary_path("libsimpleperf_report.so")


unittest.main(argv=[sys.argv[0]] + remaining)
