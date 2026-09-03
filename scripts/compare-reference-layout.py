#!/usr/bin/env python3
"""Compare an AArch64 NDK tree with the normalized r27d Linux x86_64 layout."""

from __future__ import annotations

import argparse
import os
from pathlib import Path
import stat
import sys


HOST_PREFIXES = (
    ("toolchains/llvm/prebuilt/linux-x86_64", "toolchains/llvm/prebuilt/linux-aarch64"),
    ("prebuilt/linux-x86_64", "prebuilt/linux-aarch64"),
    ("shader-tools/linux-x86_64", "shader-tools/linux-aarch64"),
    ("simpleperf/bin/linux/x86_64", "simpleperf/bin/linux/aarch64"),
)


def map_host_name(value: str) -> str:
    for source, target in HOST_PREFIXES:
        if value == source or value.startswith(source + "/"):
            value = target + value[len(source) :]
            break
    if value.startswith("toolchains/llvm/prebuilt/linux-aarch64/"):
        if value.endswith("/lib/x86_64-unknown-linux-gnu"):
            value = value[: -len("x86_64-unknown-linux-gnu")] + "aarch64-unknown-linux-gnu"
        value = value.replace(
            "/lib/x86_64-unknown-linux-gnu/",
            "/lib/aarch64-unknown-linux-gnu/",
        )
        if "/python3/" in value or "/lib/python3.11/" in value:
            value = value.replace("x86_64-linux-gnu", "aarch64-linux-gnu")
    return value


def map_link_target(value: str) -> str:
    return (
        value.replace("linux-x86_64", "linux-aarch64")
        .replace("x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu")
        .replace("x86_64-linux-gnu", "aarch64-linux-gnu")
    )


def entry_type(path: Path) -> str:
    mode = path.lstat().st_mode
    if stat.S_ISDIR(mode):
        return "directory"
    if stat.S_ISREG(mode):
        return "file"
    if stat.S_ISLNK(mode):
        return "symlink"
    return "other"


def inventory(
    root: Path, normalize: bool
) -> dict[str, tuple[str, str | None, int | None]]:
    result: dict[str, tuple[str, str | None, int | None]] = {}
    for base, dirs, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        names = sorted(dirs + files)
        for name in names:
            path = base_path / name
            relative = path.relative_to(root).as_posix()
            if normalize:
                relative = map_host_name(relative)
            kind = entry_type(path)
            link = os.readlink(path) if kind == "symlink" else None
            mode = None if kind == "symlink" else stat.S_IMODE(path.lstat().st_mode)
            if normalize and link is not None:
                link = map_link_target(link)
            result[relative] = (kind, link, mode)
    return result


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "candidate",
        type=Path,
        help="assembled android-ndk-r27d Linux AArch64 directory",
    )
    parser.add_argument(
        "--reference",
        type=Path,
        default=Path("/mnt/develop/android-ndk-r27d"),
    )
    parser.add_argument("--limit", type=int, default=100)
    args = parser.parse_args()

    expected = inventory(args.reference, normalize=True)
    actual = inventory(args.candidate, normalize=False)
    missing = sorted(expected.keys() - actual.keys())
    extra = sorted(actual.keys() - expected.keys())
    common = sorted(expected.keys() & actual.keys())
    type_mismatches = [
        path for path in common if expected[path][0] != actual[path][0]
    ]
    link_mismatches = [
        path
        for path in common
        if expected[path][0] == actual[path][0] == "symlink"
        and expected[path][1] != actual[path][1]
    ]
    mode_mismatches = [
        path
        for path in common
        if expected[path][0] == actual[path][0] != "symlink"
        and expected[path][2] != actual[path][2]
    ]

    print(f"reference_entries={len(expected)}")
    print(f"candidate_entries={len(actual)}")
    for label, values in (
        ("missing", missing),
        ("extra", extra),
        ("type_mismatches", type_mismatches),
        ("link_mismatches", link_mismatches),
        ("mode_mismatches", mode_mismatches),
    ):
        print(f"{label}={len(values)}")
        for value in values[: args.limit]:
            if label == "link_mismatches":
                print(
                    f"  {value}: expected={expected[value][1]!r} "
                    f"actual={actual[value][1]!r}"
                )
            elif label == "type_mismatches":
                print(
                    f"  {value}: expected={expected[value][0]} "
                    f"actual={actual[value][0]}"
                )
            elif label == "mode_mismatches":
                print(
                    f"  {value}: expected={expected[value][2]:#05o} "
                    f"actual={actual[value][2]:#05o}"
                )
            else:
                print(f"  {value}")

    return (
        1
        if missing or extra or type_mismatches or link_mismatches or mode_mismatches
        else 0
    )


if __name__ == "__main__":
    sys.exit(main())
