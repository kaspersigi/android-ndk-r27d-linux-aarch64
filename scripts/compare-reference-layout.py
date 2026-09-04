#!/usr/bin/env python3
"""Compare an AArch64 NDK tree with the normalized r27d Linux x86_64 layout."""

from __future__ import annotations

import ast
import argparse
from dataclasses import dataclass
import hashlib
import os
from pathlib import Path
import stat
import sys

sys.dont_write_bytecode = True
script_dir = str(Path(__file__).resolve().parent)
if script_dir not in sys.path:
    sys.path.insert(0, script_dir)
from elf_validation import is_valid_elf_machine


HOST_PREFIXES = (
    ("toolchains/llvm/prebuilt/linux-x86_64", "toolchains/llvm/prebuilt/linux-aarch64"),
    ("prebuilt/linux-x86_64", "prebuilt/linux-aarch64"),
    ("shader-tools/linux-x86_64", "shader-tools/linux-aarch64"),
    ("simpleperf/bin/linux/x86_64", "simpleperf/bin/linux/aarch64"),
)

EXPECTED_REFERENCE_ENTRIES = 9276
EXPECTED_REFERENCE_REVISION = "27.3.13750724"

REFERENCE_X86_64_ROOTS = tuple(source for source, _ in HOST_PREFIXES)
REFERENCE_AARCH64_ROOTS = tuple(target for _, target in HOST_PREFIXES)

HOST_SCRIPT_DIFFERENCES = {
    "build/cmake/android-legacy.toolchain.cmake",
    "build/cmake/android.toolchain.cmake",
    "build/ndk-build",
    "build/tools/make_standalone_toolchain.py",
    "build/tools/ndk_bin_common.sh",
    "ndk-gdb",
    "ndk-lldb",
    "ndk-stack",
    "ndk-which",
}

HOST_SCRIPT_MANIFEST = (
    Path(__file__).resolve().parents[1] / "manifests/ndk-host-scripts.tsv"
)
PROJECT_ROOT = Path(__file__).resolve().parents[1]
HOST_GENERATED_TEXT_MANIFEST = (
    PROJECT_ROOT / "manifests/ndk-host-generated-text.tsv"
)

PYTHON_CONFIG_FILES = {
    "toolchains/llvm/prebuilt/linux-aarch64/python3/include/python3.11/pyconfig.h",
    "toolchains/llvm/prebuilt/linux-aarch64/python3/lib/pkgconfig/python-3.11-embed.pc",
    "toolchains/llvm/prebuilt/linux-aarch64/python3/lib/pkgconfig/python-3.11.pc",
    "toolchains/llvm/prebuilt/linux-aarch64/python3/lib/python3.11/"
    "_sysconfigdata__linux_aarch64-linux-gnu.py",
}

COMPILER_RT_GENERATED_TEXT_PREFIX = (
    "toolchains/llvm/prebuilt/linux-aarch64/lib/clang/18/lib/"
    "aarch64-unknown-linux-gnu/"
)

HOST_GENERATED_CONTENT_PREFIXES = (
    "toolchains/llvm/prebuilt/linux-aarch64/lib/aarch64-unknown-linux-gnu",
    "toolchains/llvm/prebuilt/linux-aarch64/lib/clang/18/lib/aarch64-unknown-linux-gnu",
)

HOST_GENERATED_CONTENT_FILES = {
    "prebuilt/linux-aarch64/lib/libyasm.a",
    "toolchains/llvm/prebuilt/linux-aarch64/lib/libbolt_rt_instr.a",
}

HOST_ELF_CONTENT_PREFIXES = (
    "prebuilt/linux-aarch64/bin",
    "shader-tools/linux-aarch64",
    "simpleperf/bin/linux/aarch64",
    "toolchains/llvm/prebuilt/linux-aarch64/bin",
    "toolchains/llvm/prebuilt/linux-aarch64/python3",
    "toolchains/llvm/prebuilt/linux-aarch64/lib/python3.11",
)

HOST_ELF_CONTENT_DIRECTORIES = {
    "toolchains/llvm/prebuilt/linux-aarch64/lib",
    "toolchains/llvm/prebuilt/linux-aarch64/musl/lib",
}


@dataclass(frozen=True)
class Entry:
    kind: str
    source: Path
    mode: int | None
    link: str | None = None
    digest: str | None = None


def package_revision(root: Path) -> str | None:
    source_properties = root / "source.properties"
    try:
        lines = source_properties.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError):
        return None
    for line in lines:
        key, separator, value = line.partition("=")
        if separator and key.strip() == "Pkg.Revision":
            return value.strip()
    return None


def reference_identity_errors(root: Path) -> list[str]:
    errors: list[str] = []
    revision = package_revision(root)
    if revision != EXPECTED_REFERENCE_REVISION:
        errors.append(
            "source.properties must report "
            f"Pkg.Revision = {EXPECTED_REFERENCE_REVISION}"
        )

    for relative in REFERENCE_X86_64_ROOTS:
        if not (root / relative).is_dir():
            errors.append(f"missing official x86_64 host directory: {relative}")
    for relative in REFERENCE_AARCH64_ROOTS:
        if (root / relative).exists() or (root / relative).is_symlink():
            errors.append(f"unexpected AArch64 host directory: {relative}")

    for base, dirs, files in os.walk(root, followlinks=False):
        base_path = Path(base)
        for name in files:
            if name.endswith((".pyc", ".pyo")):
                errors.append(
                    "generated Python bytecode is not allowed in the reference: "
                    f"{(base_path / name).relative_to(root).as_posix()}"
                )
                return errors
        if base_path.name == "__pycache__" and (dirs or files):
            errors.append(
                "non-empty __pycache__ is not allowed in the reference: "
                f"{base_path.relative_to(root).as_posix()}"
            )
            return errors
    return errors


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


def file_digest(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_host_script_digests(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split()
        if len(fields) != 2 or len(fields[0]) != 64:
            raise ValueError(
                f"invalid host-script manifest entry at {path}:{line_number}"
            )
        digest, relative = fields
        try:
            bytes.fromhex(digest)
        except ValueError as error:
            raise ValueError(
                f"invalid SHA-256 at {path}:{line_number}"
            ) from error
        if relative in result:
            raise ValueError(f"duplicate host-script manifest path: {relative}")
        result[relative] = digest.lower()

    manifest_paths = set(result)
    if manifest_paths != HOST_SCRIPT_DIFFERENCES:
        missing = sorted(HOST_SCRIPT_DIFFERENCES - manifest_paths)
        extra = sorted(manifest_paths - HOST_SCRIPT_DIFFERENCES)
        raise ValueError(
            "host-script manifest path set differs from the patched scripts: "
            f"missing={missing} extra={extra}"
        )
    return result


def is_host_generated_text_path(relative: str) -> bool:
    return relative in PYTHON_CONFIG_FILES or (
        relative.startswith(COMPILER_RT_GENERATED_TEXT_PREFIX)
        and relative.endswith(".syms")
    )


def read_generated_text_digests(path: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        fields = stripped.split()
        if len(fields) != 2 or len(fields[0]) != 64:
            raise ValueError(
                f"invalid generated-text manifest entry at {path}:{line_number}"
            )
        digest, relative = fields
        try:
            bytes.fromhex(digest)
        except ValueError as error:
            raise ValueError(f"invalid SHA-256 at {path}:{line_number}") from error
        if not is_host_generated_text_path(relative):
            raise ValueError(
                f"unexpected generated-text manifest path at {path}:{line_number}: "
                f"{relative}"
            )
        if relative in result:
            raise ValueError(f"duplicate generated-text manifest path: {relative}")
        result[relative] = digest.lower()
    return result


def normalized_generated_text_digest(path: Path) -> str:
    content = path.read_bytes().replace(
        os.fsencode(PROJECT_ROOT), b"${PROJECT_ROOT}"
    )
    return hashlib.sha256(content).hexdigest()


def pkg_config_is_valid(relative: str, content: str) -> bool:
    variables: dict[str, str] = {}
    fields: dict[str, str] = {}
    for line in content.splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if "=" in line and (":" not in line or line.index("=") < line.index(":")):
            key, value = line.split("=", 1)
            variables[key.strip()] = value.strip()
        elif ":" in line:
            key, value = line.split(":", 1)
            fields[key.strip()] = value.strip()
        else:
            return False

    expected_prefix = str(PROJECT_ROOT / "out/python-linux-aarch64")
    expected_description = (
        "Embed Python into an application"
        if relative.endswith("python-3.11-embed.pc")
        else "Build a C extension for Python"
    )
    expected_libs = (
        "-L${libdir} -lpython3.11"
        if relative.endswith("python-3.11-embed.pc")
        else ""
    )
    private_libs = fields.pop("Libs.private", "").split()
    return variables == {
        "prefix": expected_prefix,
        "exec_prefix": "${prefix}",
        "libdir": "${exec_prefix}/lib",
        "includedir": "${prefix}/include",
    } and fields == {
        "Name": "Python",
        "Description": expected_description,
        "Requires": "",
        "Version": "3.11",
        "Libs": expected_libs,
        "Cflags": "-I${includedir}/python3.11",
    } and private_libs == ["-ldl", "-lpthread"]


def sysconfig_is_valid(content: str) -> bool:
    try:
        module = ast.parse(content)
        if len(module.body) != 1 or not isinstance(module.body[0], ast.Assign):
            return False
        assignment = module.body[0]
        if (
            len(assignment.targets) != 1
            or not isinstance(assignment.targets[0], ast.Name)
            or assignment.targets[0].id != "build_time_vars"
        ):
            return False
        values = ast.literal_eval(assignment.value)
    except (SyntaxError, ValueError):
        return False
    if not isinstance(values, dict):
        return False
    expected = {
        "AR": "aarch64-linux-gnu-ar",
        "BUILD_GNU_TYPE": "x86_64-pc-linux-gnu",
        "CC": "aarch64-linux-gnu-gcc",
        "CXX": "aarch64-linux-gnu-g++",
        "EXT_SUFFIX": ".cpython-311-aarch64-linux-gnu.so",
        "HOST_GNU_TYPE": "aarch64-unknown-linux-gnu",
        "INSTSONAME": "libpython3.11.so.1.0",
        "LDLIBRARY": "libpython3.11.so",
        "LDVERSION": "3.11",
        "LIBRARY": "libpython3.11.a",
        "MACHDEP": "linux",
        "MULTIARCH": "aarch64-linux-gnu",
        "Py_ENABLE_SHARED": 1,
        "SIZEOF_VOID_P": 8,
        "SOABI": "cpython-311-aarch64-linux-gnu",
        "VERSION": "3.11",
        "prefix": str(PROJECT_ROOT / "out/python-linux-aarch64"),
        "exec_prefix": str(PROJECT_ROOT / "out/python-linux-aarch64"),
    }
    return all(values.get(key) == value for key, value in expected.items())


def generated_text_is_valid(relative: str, path: Path) -> bool:
    expected_digest = PINNED_GENERATED_TEXT_DIGESTS.get(relative)
    if expected_digest is None:
        return False
    try:
        content = path.read_text(encoding="utf-8")
        if normalized_generated_text_digest(path) != expected_digest:
            return False
    except (OSError, UnicodeError):
        return False

    if relative.endswith("pyconfig.h"):
        required_defines = {
            "#define HAVE_DLOPEN 1",
            "#define Py_ENABLE_SHARED 1",
            "#define SIZEOF_VOID_P 8",
        }
        return required_defines.issubset(set(content.splitlines()))
    if relative.endswith(".pc"):
        return pkg_config_is_valid(relative, content)
    if relative.endswith("_sysconfigdata__linux_aarch64-linux-gnu.py"):
        return sysconfig_is_valid(content)
    if relative.endswith(".syms"):
        lines = [line.strip() for line in content.splitlines()]
        return (
            len(lines) >= 3
            and lines[0] == "{"
            and lines[-1] == "};"
            and all(line and line.endswith(";") for line in lines[1:-1])
        )
    return False


PINNED_HOST_SCRIPT_DIGESTS = read_host_script_digests(HOST_SCRIPT_MANIFEST)
PINNED_GENERATED_TEXT_DIGESTS = read_generated_text_digests(
    HOST_GENERATED_TEXT_MANIFEST
)


def is_rebuilt_host_elf_path(relative: str) -> bool:
    if any(
        relative.startswith(prefix + "/") for prefix in HOST_ELF_CONTENT_PREFIXES
    ):
        return True
    parent, separator, _ = relative.rpartition("/")
    return bool(separator) and parent in HOST_ELF_CONTENT_DIRECTORIES


def content_difference_is_expected(
    relative: str, expected: Entry, actual: Entry
) -> bool:
    if relative in HOST_SCRIPT_DIFFERENCES:
        return actual.digest == PINNED_HOST_SCRIPT_DIGESTS[relative]
    if is_host_generated_text_path(relative):
        return generated_text_is_valid(relative, actual.source)
    if relative in HOST_GENERATED_CONTENT_FILES:
        return True
    if any(
        relative == prefix or relative.startswith(prefix + "/")
        for prefix in HOST_GENERATED_CONTENT_PREFIXES
    ):
        return True
    # A machine transition is valid only in an explicitly identified host
    # position. Android target ELFs below the host-tagged sysroot and Clang
    # runtime directories must remain byte-for-byte identical.
    return (
        is_rebuilt_host_elf_path(relative)
        and is_valid_elf_machine(expected.source, 62)
        and is_valid_elf_machine(actual.source, 183)
    )


def inventory(root: Path, normalize: bool) -> dict[str, Entry]:
    result: dict[str, Entry] = {}
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
            if relative in result:
                raise ValueError(f"normalized path collision: {relative}")
            digest = file_digest(path) if kind == "file" else None
            result[relative] = Entry(
                kind=kind,
                source=path,
                mode=mode,
                link=link,
                digest=digest,
            )
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

    try:
        reference_root = args.reference.resolve(strict=True)
        candidate_root = args.candidate.resolve(strict=True)
    except OSError as error:
        print(f"error: cannot resolve input tree: {error}", file=sys.stderr)
        return 1

    if reference_root == candidate_root:
        print(
            "error: candidate and reference must be different directories",
            file=sys.stderr,
        )
        return 1

    identity_errors = reference_identity_errors(reference_root)
    if identity_errors:
        for error in identity_errors:
            print(
                f"error: invalid official Linux x86_64 reference: {error}",
                file=sys.stderr,
            )
        return 1

    expected = inventory(reference_root, normalize=True)
    actual = inventory(candidate_root, normalize=False)
    missing = sorted(expected.keys() - actual.keys())
    extra = sorted(actual.keys() - expected.keys())
    common = sorted(expected.keys() & actual.keys())
    type_mismatches = [
        path for path in common if expected[path].kind != actual[path].kind
    ]
    link_mismatches = [
        path
        for path in common
        if expected[path].kind == actual[path].kind == "symlink"
        and expected[path].link != actual[path].link
    ]
    mode_mismatches = [
        path
        for path in common
        if expected[path].kind == actual[path].kind != "symlink"
        and expected[path].mode != actual[path].mode
    ]
    content_mismatches = [
        path
        for path in common
        if expected[path].kind == actual[path].kind == "file"
        and (
            (
                (path in HOST_SCRIPT_DIFFERENCES or is_host_generated_text_path(path))
                and not content_difference_is_expected(
                    path, expected[path], actual[path]
                )
            )
            or (
                path not in HOST_SCRIPT_DIFFERENCES
                and not is_host_generated_text_path(path)
                and expected[path].digest != actual[path].digest
                and not content_difference_is_expected(
                    path, expected[path], actual[path]
                )
            )
        )
    ]
    reference_entry_count_mismatch = len(expected) != EXPECTED_REFERENCE_ENTRIES

    print(f"reference_entries={len(expected)}")
    print(f"candidate_entries={len(actual)}")
    for label, values in (
        ("missing", missing),
        ("extra", extra),
        ("type_mismatches", type_mismatches),
        ("link_mismatches", link_mismatches),
        ("mode_mismatches", mode_mismatches),
        ("content_mismatches", content_mismatches),
    ):
        print(f"{label}={len(values)}")
        for value in values[: args.limit]:
            if label == "link_mismatches":
                print(
                    f"  {value}: expected={expected[value].link!r} "
                    f"actual={actual[value].link!r}"
                )
            elif label == "type_mismatches":
                print(
                    f"  {value}: expected={expected[value].kind} "
                    f"actual={actual[value].kind}"
                )
            elif label == "mode_mismatches":
                print(
                    f"  {value}: expected={expected[value].mode:#05o} "
                    f"actual={actual[value].mode:#05o}"
                )
            elif label == "content_mismatches":
                print(
                    f"  {value}: expected_sha256={expected[value].digest} "
                    f"actual_sha256={actual[value].digest}"
                )
            else:
                print(f"  {value}")

    if reference_entry_count_mismatch:
        print(
            "reference_entry_count_mismatch=1 "
            f"expected={EXPECTED_REFERENCE_ENTRIES} actual={len(expected)}"
        )
    else:
        print("reference_entry_count_mismatch=0")

    return 1 if (
        reference_entry_count_mismatch
        or missing
        or extra
        or type_mismatches
        or link_mismatches
        or mode_mismatches
        or content_mismatches
    ) else 0


if __name__ == "__main__":
    sys.exit(main())
