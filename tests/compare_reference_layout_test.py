#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

from __future__ import annotations

from pathlib import Path
import runpy
import tempfile
import unittest


PROJECT_ROOT = Path(__file__).resolve().parents[1]
MODULE = runpy.run_path(str(PROJECT_ROOT / "scripts/compare-reference-layout.py"))
Entry = MODULE["Entry"]
content_difference_is_expected = MODULE["content_difference_is_expected"]
reference_identity_errors = MODULE["reference_identity_errors"]


def write_elf(path: Path, machine: int) -> None:
    header = bytearray(20)
    header[:4] = b"\x7fELF"
    header[5] = 1
    header[18:20] = machine.to_bytes(2, "little")
    path.write_bytes(header)


class HostElfDifferenceTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        root = Path(self.temporary_directory.name)
        self.reference = root / "reference"
        self.candidate = root / "candidate"
        write_elf(self.reference, 62)
        write_elf(self.candidate, 183)
        self.expected = Entry("file", self.reference, 0o755)
        self.actual = Entry("file", self.candidate, 0o755)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_rebuilt_host_elf_positions_are_allowed(self) -> None:
        paths = (
            "prebuilt/linux-aarch64/bin/make",
            "shader-tools/linux-aarch64/glslc",
            "simpleperf/bin/linux/aarch64/simpleperf",
            "toolchains/llvm/prebuilt/linux-aarch64/bin/clang-18",
            "toolchains/llvm/prebuilt/linux-aarch64/lib/liblldb.so",
            "toolchains/llvm/prebuilt/linux-aarch64/musl/lib/libclang.so",
            "toolchains/llvm/prebuilt/linux-aarch64/python3/bin/python3.11",
            "toolchains/llvm/prebuilt/linux-aarch64/lib/python3.11/host.so",
        )
        for relative in paths:
            with self.subTest(relative=relative):
                self.assertTrue(
                    content_difference_is_expected(
                        relative, self.expected, self.actual
                    )
                )

    def test_android_target_elf_positions_are_rejected(self) -> None:
        paths = (
            "toolchains/llvm/prebuilt/linux-aarch64/sysroot/usr/lib/"
            "x86_64-linux-android/21/crtbegin_dynamic.o",
            "toolchains/llvm/prebuilt/linux-aarch64/lib/clang/18/lib/linux/"
            "libclang_rt.asan-x86_64-android.so",
            "sources/android/x86_64/target.so",
        )
        for relative in paths:
            with self.subTest(relative=relative):
                self.assertFalse(
                    content_difference_is_expected(
                        relative, self.expected, self.actual
                    )
                )


class ReferenceIdentityTest(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.reference = Path(self.temporary_directory.name) / "reference"
        self.reference.mkdir()
        (self.reference / "source.properties").write_text(
            "Pkg.Desc = Android NDK\nPkg.Revision = 27.3.13750724\n",
            encoding="utf-8",
        )
        for relative in MODULE["REFERENCE_X86_64_ROOTS"]:
            (self.reference / relative).mkdir(parents=True)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_clean_official_x86_64_identity_is_accepted(self) -> None:
        self.assertEqual(reference_identity_errors(self.reference), [])

    def test_aarch64_product_is_rejected_as_reference(self) -> None:
        aarch64_root = self.reference / MODULE["REFERENCE_AARCH64_ROOTS"][0]
        aarch64_root.mkdir(parents=True)
        errors = reference_identity_errors(self.reference)
        self.assertTrue(any("unexpected AArch64" in error for error in errors))

    def test_generated_python_bytecode_is_rejected(self) -> None:
        bytecode = self.reference / "build/__pycache__/module.pyc"
        bytecode.parent.mkdir(parents=True)
        bytecode.write_bytes(b"generated")
        errors = reference_identity_errors(self.reference)
        self.assertTrue(any("Python bytecode" in error for error in errors))


if __name__ == "__main__":
    unittest.main()
