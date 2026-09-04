#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0

import argparse
import hashlib
import os
import stat
import sys
from pathlib import Path


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inventory(root: Path) -> dict[str, tuple[str, int, str]]:
    entries: dict[str, tuple[str, int, str]] = {}

    def visit(directory: Path, prefix: Path) -> None:
        children = sorted(os.scandir(directory), key=lambda entry: os.fsencode(entry.name))
        for child in children:
            relative = prefix / child.name
            relative_text = relative.as_posix()
            path = Path(child.path)
            metadata = child.stat(follow_symlinks=False)
            mode = stat.S_IMODE(metadata.st_mode)
            if stat.S_ISLNK(metadata.st_mode):
                entries[relative_text] = ("symlink", mode, os.readlink(path))
            elif stat.S_ISDIR(metadata.st_mode):
                entries[relative_text] = ("directory", mode, "")
                visit(path, relative)
            elif stat.S_ISREG(metadata.st_mode):
                entries[relative_text] = ("file", mode, file_digest(path))
            else:
                raise ValueError(f"unsupported entry type: {path}")

    visit(root, Path())
    return entries


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Compare an assembled tree with the tree extracted from its archive."
    )
    parser.add_argument("expected", type=Path)
    parser.add_argument("actual", type=Path)
    args = parser.parse_args()
    if not args.expected.is_dir() or not args.actual.is_dir():
        parser.error("both arguments must be directories")

    expected = inventory(args.expected)
    actual = inventory(args.actual)
    differences: list[str] = []
    for relative in sorted(expected.keys() | actual.keys(), key=os.fsencode):
        if relative not in actual:
            differences.append(f"missing: {relative}")
        elif relative not in expected:
            differences.append(f"extra: {relative}")
        elif expected[relative] != actual[relative]:
            differences.append(
                f"mismatch: {relative}: expected={expected[relative]} actual={actual[relative]}"
            )

    print(f"assembled_entries={len(expected)}")
    print(f"extracted_entries={len(actual)}")
    print(f"archive_tree_differences={len(differences)}")
    for difference in differences[:100]:
        print(difference, file=sys.stderr)
    if len(differences) > 100:
        print(f"... {len(differences) - 100} more differences", file=sys.stderr)
    return 1 if differences else 0


if __name__ == "__main__":
    raise SystemExit(main())
