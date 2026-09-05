#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""NDK consumer entry-point contract; identical in the NDK and SDK repositories.

Default: cheap host-discovery/configuration checks, no native compilation.
--runtime: also exercise packaged Python/launchers and compile C/C++ through
every CMake route. On x86_64, QEMU plus binfmt and the AArch64 sysroot are required.
Only uname is simulated for host CMake; no Android host-tag override is allowed.
"""
from __future__ import annotations

import argparse
import importlib
import os
from pathlib import Path
import platform
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
from types import SimpleNamespace


class EntryPoints(unittest.TestCase):
    def debugger(self):
        sys.path.insert(0, str(NDK / "prebuilt/linux-aarch64/bin/ndkgdb.pyz"))
        return importlib.import_module("ndkgdb")

    def test_debugger_package_root_and_api(self):
        debugger = self.debugger()
        self.assertEqual(Path(debugger.NDK_PATH), NDK)
        self.assertEqual(debugger.get_api_level(SimpleNamespace(get_prop=lambda _: "35")), 35)

    def test_debugger_main_server_selection(self):
        debugger = self.debugger()
        device = SimpleNamespace(shell_nocheck=lambda _: (1, "", ""), adb_cmd=["adb"])
        args = SimpleNamespace(device=device, no_lldb=False, package_name="dev.probe", launch=False)
        class StopBeforeDeviceWrites(Exception):
            pass
        for abi, arch in (("armeabi-v7a", "arm"), ("arm64-v8a", "aarch64"),
                          ("x86", "i386"), ("x86_64", "x86_64")):
            with self.subTest(abi=abi), patch.object(platform, "machine", return_value="aarch64"), \
                    patch.object(debugger, "advise_apk_debugging"), \
                    patch.object(debugger, "handle_args", return_value=args), \
                    patch.object(debugger, "find_project", return_value=str(NDK)), \
                    patch.object(debugger, "fetch_abi", return_value=abi), \
                    patch.object(debugger, "dump_var", return_value="obj"), \
                    patch.object(debugger, "get_app_data_dir", return_value="/data/user/0/dev.probe"), \
                    patch.object(debugger.subprocess, "check_output", return_value=b"simulated adb version"), \
                    patch.object(debugger, "get_debugger_server_path", side_effect=StopBeforeDeviceWrites) as stop:
                with self.assertRaises(StopBeforeDeviceWrites):
                    debugger.main()
                selected = Path(stop.call_args.args[-1])
                expected = NDK / "toolchains/llvm/prebuilt/linux-aarch64/lib/clang/18/lib/linux" / arch / "lldb-server"
                self.assertEqual(selected, expected)
                self.assertTrue(selected.is_file())

    def test_debugger_host_discovery(self):
        debugger = self.debugger()
        for system, machine, expected in (
            ("linux", "aarch64", "linux-aarch64"),
            ("linux", "arm64", "linux-aarch64"),
            ("linux", "x86_64", "linux-x86_64"),
            ("darwin", "arm64", "darwin-x86_64"),
            ("win32", "ARM64", "windows-x86_64"),
        ):
            with self.subTest(system=system, machine=machine), \
                    patch.object(sys, "platform", system), \
                    patch.object(platform, "machine", return_value=machine):
                self.assertEqual(debugger.get_llvm_host_name(), expected)
                if expected == "linux-aarch64":
                    toolchain = NDK / "toolchains/llvm/prebuilt" / debugger.get_llvm_host_name()
                    self.assertIsNotNone(debugger.get_lldb_path(str(toolchain)))
                    self.assertTrue(debugger.get_llvm_package_version(str(toolchain)))

    def test_simpleperf_default_library_discovery(self):
        sys.path.insert(0, str(NDK / "simpleperf"))
        report = importlib.import_module("simpleperf_report_lib")
        class StopBeforeLoading(Exception):
            pass
        expected = NDK / "simpleperf/bin/linux/aarch64/libsimpleperf_report.so"
        for machine in ("aarch64", "arm64"):
            with self.subTest(machine=machine), \
                    patch.object(sys, "platform", "linux"), \
                    patch.object(platform, "machine", return_value=machine), \
                    patch.object(report.ct, "CDLL", side_effect=StopBeforeLoading) as load:
                with self.assertRaises(StopBeforeLoading):
                    report.ReportLib()
                self.assertEqual(Path(load.call_args.args[0]).resolve(), expected)

    def test_cmake_entrypoints(self):
        with tempfile.TemporaryDirectory(prefix="ndk entrypoints ") as temporary:
            root = Path(temporary)
            source = root / "source"
            source.mkdir()
            (source / "CMakeLists.txt").write_text(
                "cmake_minimum_required(VERSION 3.22)\n"
                + ("project(probe LANGUAGES C CXX)\n"
                   "add_library(probe SHARED probe.c probe.cpp)\n"
                   "target_compile_features(probe PRIVATE cxx_std_17)\n"
                   if ARGS.runtime else "project(probe LANGUAGES NONE)\n")
                + 'file(WRITE "${CMAKE_BINARY_DIR}/selected.txt" '
                  '"${ANDROID_HOST_TAG}\n${CMAKE_ANDROID_NDK_TOOLCHAIN_HOST_TAG}\n'
                  '${CMAKE_ANDROID_NDK_TOOLCHAIN_UNIFIED}\n${CMAKE_C_COMPILER}\n")\n'
            )
            (source / "probe.c").write_text("int c_probe(void) { return 42; }\n")
            (source / "probe.cpp").write_text(
                '#include <string>\nextern "C" int cpp_probe() { return std::string("arm64").size(); }\n'
            )
            # CMake invokes external uname even when its own ELF runs under QEMU.
            uname = root / "uname"
            uname.write_text('#!/bin/sh\ncase "$1" in -m|-p) echo aarch64;; *) exec /usr/bin/uname "$@";; esac\n')
            uname.chmod(0o755)
            for index, executable in enumerate(ARGS.cmake):
                cmake = shutil.which(executable)
                self.assertIsNotNone(cmake, f"missing CMake dependency: {executable}")
                cmake = str(Path(cmake).resolve())
                for route in ("legacy", "modern", "builtin"):
                    with self.subTest(cmake=cmake, route=route):
                        build = root / f"build-{index}-{route}"
                        command = [cmake, "-S", str(source), "-B", str(build), "-G", "Ninja",
                                   "-DCMAKE_BUILD_TYPE=Release"]
                        sibling_ninja = Path(cmake).parent / "ninja"
                        if ARGS.ninja:
                            command += [f"-DCMAKE_MAKE_PROGRAM={ARGS.ninja}"]
                        elif sibling_ninja.is_file():
                            command += [f"-DCMAKE_MAKE_PROGRAM={sibling_ninja}"]
                        if platform.machine().lower() not in ("aarch64", "arm64"):
                            command += [f"-DCMAKE_UNAME={uname}"]
                        if route == "builtin":
                            command += ["-DCMAKE_SYSTEM_NAME=Android", "-DCMAKE_SYSTEM_VERSION=21",
                                        "-DCMAKE_ANDROID_ARCH_ABI=arm64-v8a", f"-DCMAKE_ANDROID_NDK={NDK}"]
                        else:
                            command += [f"-DCMAKE_TOOLCHAIN_FILE={NDK}/build/cmake/android.toolchain.cmake",
                                        "-DANDROID_ABI=arm64-v8a", "-DANDROID_PLATFORM=android-21"]
                            if route == "modern":
                                command += ["-DANDROID_USE_LEGACY_TOOLCHAIN_FILE=OFF"]
                        # Reconfigure exercises persisted CMakeSystem.cmake as well.
                        for _ in range(2):
                            result = subprocess.run(command, env=ENV, text=True, capture_output=True, timeout=180)
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                            selected = (build / "selected.txt").read_text()
                            self.assertIn("linux-aarch64", selected)
                            self.assertNotIn("linux-x86", selected)
                            if route != "legacy":
                                self.assertIn(str(NDK / "toolchains/llvm/prebuilt/linux-aarch64"), selected)
                        if ARGS.runtime:
                            result = subprocess.run([cmake, "--build", str(build), "--parallel", JOBS],
                                                    env=ENV, text=True, capture_output=True, timeout=180)
                            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                            header = (build / "libprobe.so").read_bytes()[:20]
                            self.assertEqual(header[:4], b"\x7fELF")
                            self.assertEqual(int.from_bytes(header[18:20], "little"), 183)
                        print(f"cmake-entrypoint-ok cmake={cmake} route={route} "
                              f"runtime={ARGS.runtime} configurations=2", flush=True)

    def test_packaged_runtime(self):
        python = NDK / "toolchains/llvm/prebuilt/linux-aarch64/python3/bin/python3.11"
        code = (
            "import pathlib, platform, sys; n=pathlib.Path(sys.argv[1]); "
            "assert platform.machine().lower() in ('aarch64', 'arm64'); "
            "sys.path.insert(0,str(n/'prebuilt/linux-aarch64/bin/ndkgdb.pyz')); "
            "import ndkgdb; assert ndkgdb.get_llvm_host_name() == 'linux-aarch64'; "
            "assert pathlib.Path(ndkgdb.NDK_PATH) == n; "
            "t=n/'toolchains/llvm/prebuilt'/ndkgdb.get_llvm_host_name(); "
            "assert ndkgdb.get_lldb_path(str(t)); assert ndkgdb.get_llvm_package_version(str(t)); "
            "sys.path.insert(0,str(n/'simpleperf')); "
            "from simpleperf_report_lib import ReportLib; r=ReportLib(); r.Close()"
        )
        subprocess.run([str(python), "-B", "-c", code, str(NDK)], env=ENV, check=True, timeout=60)

    def test_shell_launchers(self):
        for launcher, option in (("ndk-gdb", "--help"), ("ndk-lldb", "--help"),
                                 ("ndk-stack", "--help"), ("ndk-which", "readelf")):
            result = subprocess.run([str(NDK / launcher), option], env=ENV,
                                    text=True, capture_output=True, timeout=60)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertNotIn("linux-x86", result.stdout + result.stderr)
            if launcher == "ndk-which":
                expected = NDK / "toolchains/llvm/prebuilt/linux-aarch64/bin/llvm-readelf"
                self.assertEqual(Path(result.stdout.strip()).resolve(), expected.resolve())

    def test_ndk_build_entrypoint(self):
        with tempfile.TemporaryDirectory(prefix="ndk-build-entrypoint-") as temporary:
            root = Path(temporary)
            jni = root / "jni"
            jni.mkdir()
            (jni / "Android.mk").write_text(
                "LOCAL_PATH := $(call my-dir)\ninclude $(CLEAR_VARS)\n"
                "LOCAL_MODULE := probe\nLOCAL_SRC_FILES := probe.cpp\ninclude $(BUILD_SHARED_LIBRARY)\n")
            (jni / "Application.mk").write_text(
                "APP_ABI := armeabi-v7a arm64-v8a x86 x86_64\nAPP_PLATFORM := android-21\nAPP_STL := c++_static\n")
            (jni / "probe.cpp").write_text(
                '#include <string>\nextern "C" int probe() { return std::string("ndk").size(); }\n')
            # Debugger calls Make directly, so it must propagate host discovery too.
            debugger = self.debugger()
            args = SimpleNamespace(make_cmd=str(NDK / "prebuilt/linux-aarch64/bin/make"), project=str(root))
            with patch.object(platform, "machine", return_value="aarch64"), patch.dict(os.environ, ENV, clear=True):
                selected = debugger.dump_var(args, "LLVM_TOOLCHAIN_PREFIX", "arm64-v8a")
            self.assertEqual(Path(selected), NDK / "toolchains/llvm/prebuilt/linux-aarch64/bin")
            command = [str(NDK / "ndk-build"), "-j" + JOBS]
            if not ARGS.runtime:
                command.append("--dry-run")
            result = subprocess.run(command, cwd=root, env=ENV,
                                    text=True, capture_output=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            if not ARGS.runtime:
                self.assertIn("linux-aarch64", result.stdout)
                self.assertNotIn("linux-x86", result.stdout)
                return
            for abi, machine in (("armeabi-v7a", 40), ("arm64-v8a", 183), ("x86", 3), ("x86_64", 62)):
                header = (root / "libs" / abi / "libprobe.so").read_bytes()[:20]
                self.assertEqual(header[:4], b"\x7fELF")
                self.assertEqual(int.from_bytes(header[18:20], "little"), machine)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ndk", type=Path, required=True)
    parser.add_argument("--cmake", action="append", help="repeat to test each bundled CMake")
    parser.add_argument("--runtime", action="store_true")
    parser.add_argument("--ninja", help="preflight-only host Ninja; default prefers CMake's bundled Ninja")
    ARGS, remaining = parser.parse_known_args()
    ARGS.cmake = ARGS.cmake or ["cmake"]
    NDK = ARGS.ndk.resolve(strict=True)
    ENV = dict(os.environ, PYTHONDONTWRITEBYTECODE="1")
    for name in ("HOST_ARCH", "HOST_TAG", "ANDROID_HOST_TAG", "GNUMAKE",
                 "ANDROID_NDK_ROOT", "ANDROID_NDK_HOME", "NDK_ROOT", "ANDROID_NDK_PYTHON",
                 "PYTHONPATH", "PYTHONHOME"):
        ENV.pop(name, None)
    ENV.setdefault("QEMU_LD_PREFIX", "/usr/aarch64-linux-gnu")
    if not ARGS.runtime:
        del EntryPoints.test_packaged_runtime
    JOBS = (os.environ.get("JOBS", "4") if os.environ.get("GITHUB_ACTIONS") == "true"
            else subprocess.check_output(["nproc"], text=True).strip())
    print("NDK entrypoints:", NDK, "runtime=" + str(ARGS.runtime), flush=True)
    with tempfile.TemporaryDirectory(prefix="ndk-host-probe-") as host_probe:
        if platform.machine().lower() not in ("aarch64", "arm64"):
            # Shell launchers execute the native host's uname, outside QEMU.
            # Simulate only OS identity, never HOST_ARCH or ANDROID_HOST_TAG.
            uname = Path(host_probe) / "uname"
            uname.write_text('#!/bin/sh\ncase "$1" in -m|-p) echo aarch64;; *) exec /usr/bin/uname "$@";; esac\n')
            uname.chmod(0o755)
            ENV["PATH"] = host_probe + os.pathsep + ENV.get("PATH", os.defpath)
        unittest.main(argv=[sys.argv[0]] + remaining, verbosity=2)
