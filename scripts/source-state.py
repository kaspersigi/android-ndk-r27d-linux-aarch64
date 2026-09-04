#!/usr/bin/env python3
"""Record and verify the exact state of generated Git source worktrees."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
from typing import Any


def git(repository: Path, *arguments: str) -> bytes:
    result = subprocess.run(
        ["git", "-c", "color.ui=false", "-C", repository, *arguments],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode:
        diagnostic = result.stderr.decode(errors="replace").strip()
        raise RuntimeError(f"git {' '.join(arguments)} failed in {repository}: {diagnostic}")
    return result.stdout


def repositories_below(root: Path) -> list[Path]:
    repositories: list[Path] = []
    if not root.is_dir():
        return repositories
    for base, directories, files in os.walk(root):
        if ".git" in directories or ".git" in files:
            repositories.append(Path(base))
        if ".git" in directories:
            directories.remove(".git")
    return sorted(repositories, key=lambda path: path.relative_to(root).as_posix())


def hash_untracked(repository: Path, digest: Any) -> None:
    paths = git(repository, "ls-files", "--others", "--exclude-standard", "-z")
    for encoded in filter(None, paths.split(b"\0")):
        relative = os.fsdecode(encoded)
        path = repository / relative
        metadata = path.lstat()
        digest.update(b"untracked\0" + encoded + b"\0")
        digest.update(f"{stat.S_IMODE(metadata.st_mode):04o}\0".encode())
        if path.is_symlink():
            digest.update(b"link\0" + os.fsencode(os.readlink(path)) + b"\0")
        elif path.is_file():
            digest.update(b"file\0")
            with path.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
        else:
            digest.update(b"other\0")


def repository_record(root: Path, repository: Path) -> dict[str, str]:
    relative = repository.relative_to(root).as_posix() or "."
    head = git(repository, "rev-parse", "--verify", "HEAD").decode().strip()
    origin = git(repository, "remote", "get-url", "origin").decode().strip()
    status = git(
        repository,
        "status",
        "--porcelain=v1",
        "-z",
        "--untracked-files=all",
        "--ignore-submodules=none",
    )
    changes = git(
        repository,
        "diff",
        "--binary",
        "--no-ext-diff",
        "--submodule=short",
        "HEAD",
        "--",
    )
    digest = hashlib.sha256()
    digest.update(b"status\0" + status + b"\0diff\0" + changes + b"\0")
    hash_untracked(repository, digest)
    return {
        "path": relative,
        "head": head,
        "origin": origin,
        "state_sha256": digest.hexdigest(),
        "dirty": bool(status),
    }


def policy_digest(paths: list[Path]) -> str:
    digest = hashlib.sha256()
    for index, path in enumerate(paths):
        if path.is_dir():
            children = sorted(
                child
                for child in path.rglob("*")
                if child.is_file()
                and "__pycache__" not in child.parts
                and child.suffix not in {".pyc", ".pyo"}
            )
        else:
            children = [path]
        for child in children:
            if not child.is_file():
                raise RuntimeError(f"policy input is not a regular file: {child}")
            relative = child.relative_to(path).as_posix() if path.is_dir() else path.name
            digest.update(f"{index}:{relative}".encode() + b"\0")
            with child.open("rb") as stream:
                for chunk in iter(lambda: stream.read(1024 * 1024), b""):
                    digest.update(chunk)
            digest.update(b"\0")
    return digest.hexdigest()


def current_manifest(source_root: Path, policy_paths: list[Path]) -> dict[str, object]:
    repositories = repositories_below(source_root)
    if not repositories:
        raise RuntimeError(f"no Git source repositories found below {source_root}")
    return {
        "format": 1,
        "policy_sha256": policy_digest(policy_paths),
        "repositories": [repository_record(source_root, repo) for repo in repositories],
    }


def write_atomic(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary = Path(temporary_name)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as stream:
            stream.write(content)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=("verify", "record"))
    parser.add_argument("source_root", type=Path)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--policy-path", action="append", type=Path, required=True)
    args = parser.parse_args()

    try:
        actual = current_manifest(args.source_root.resolve(), args.policy_path)
        serialized = json.dumps(actual, indent=2, sort_keys=True) + "\n"
        if args.action == "record":
            write_atomic(args.manifest, serialized)
            print(f"Recorded source state: {args.manifest}")
            return 0

        if not args.manifest.is_file():
            dirty = [item["path"] for item in actual["repositories"] if item["dirty"]]
            if dirty:
                print(
                    "error: source trees are modified but have no successful-build state "
                    "manifest; run a clean build",
                    file=sys.stderr,
                )
                for path in dirty:
                    print(f"  {path}", file=sys.stderr)
                return 1
            print("Source trees are clean and pinned; state will be recorded after building.")
            return 0

        expected = json.loads(args.manifest.read_text(encoding="utf-8"))
        if expected != actual:
            print(
                "error: source state differs from the last successful build; run a clean build",
                file=sys.stderr,
            )
            return 1
        print(f"Verified source state: {len(actual['repositories'])} repositories")
        return 0
    except (OSError, RuntimeError, ValueError, json.JSONDecodeError) as error:
        print(f"error: cannot verify source state: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
