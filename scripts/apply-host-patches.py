#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
"""Apply the exact same r27d host patches in preflight and package assembly."""
from __future__ import annotations

import argparse
import copy
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PYZ = Path("prebuilt/linux-aarch64/bin/ndkgdb.pyz")


def apply_patch(root: Path, name: str) -> None:
    source = ROOT / "patches" / name
    # Official ZIP scripts are read-only; preserve their original modes.
    modes = {}
    for line in source.read_text().splitlines():
        if line.startswith("+++ b/"):
            path = root / line[6:]
            modes[path] = stat.S_IMODE(path.stat().st_mode)
            path.chmod(modes[path] | stat.S_IWUSR)
    try:
        with source.open("rb") as stream:
            subprocess.run(["patch", "--batch", "--fuzz=0", "--forward",
                            "--no-backup-if-mismatch", "-p1", "-d", str(root)],
                           stdin=stream, check=True)
    finally:
        for path, mode in modes.items():
            path.chmod(mode)


def patch_ndk(root: Path) -> None:
    for name in ("ndk-linux-aarch64-host-tag.patch", "simpleperf-linux-aarch64-host.patch",
                 "cmake-native-linux-aarch64-host.patch", "ndk-which-linux-aarch64-host.patch"):
        apply_patch(root, name)
    archive = root / PYZ
    with tempfile.TemporaryDirectory(prefix="ndkgdb-patch-") as temporary:
        work = Path(temporary)
        result = work / "patched.pyz"
        with zipfile.ZipFile(archive) as original:
            names = original.namelist()
            if len(names) != len(set(names)) or names.count("ndkgdb.py") != 1:
                raise RuntimeError("unexpected or duplicate ndkgdb.pyz members")
            if archive.read_bytes()[:4] != b"PK\x03\x04":
                raise RuntimeError("unexpected ndkgdb.pyz prefix")
            (work / "ndkgdb.py").write_bytes(original.read("ndkgdb.py"))
            apply_patch(work, "ndkgdb-linux-aarch64-host.patch")
            with zipfile.ZipFile(result, "w") as output:
                output.comment = original.comment
                for info in original.infolist():
                    data = ((work / "ndkgdb.py").read_bytes() if info.filename == "ndkgdb.py"
                            else original.read(info.filename))
                    output.writestr(copy.copy(info), data)
        mode = stat.S_IMODE(archive.stat().st_mode)
        archive.chmod(mode | stat.S_IWUSR)
        try:
            shutil.copyfile(result, archive)
        finally:
            archive.chmod(mode)


def prepare_reference(reference: Path, root: Path) -> None:
    """Metadata-only fixture, never a distributable NDK or a runtime test.

    The official x86 toolchain is linked solely for metadata/sysroot discovery;
    preflight permits version/metadata queries, LANGUAGES NONE configuration,
    and Make dry runs, but never compiles with this fixture.
    """
    root.mkdir()  # Refuse to modify an existing tree.
    for directory in ("build", "meta", "simpleperf"):
        shutil.copytree(reference / directory, root / directory)
    for name in ("source.properties", "ndk-gdb", "ndk-lldb", "ndk-stack", "ndk-which", "ndk-build"):
        shutil.copy2(reference / name, root / name)
    shutil.copytree(reference / "prebuilt/linux-x86_64", root / "prebuilt/linux-aarch64")
    llvm = root / "toolchains/llvm/prebuilt/linux-aarch64"
    llvm.parent.mkdir(parents=True)
    llvm.symlink_to(reference / "toolchains/llvm/prebuilt/linux-x86_64", target_is_directory=True)
    (root / "simpleperf/bin/linux/x86_64").rename(root / "simpleperf/bin/linux/aarch64")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("ndk", type=Path)
    parser.add_argument("--prepare-reference", type=Path)
    args = parser.parse_args()
    if args.prepare_reference:
        prepare_reference(args.prepare_reference.resolve(strict=True), args.ndk)
    patch_ndk(args.ndk.resolve(strict=True))
