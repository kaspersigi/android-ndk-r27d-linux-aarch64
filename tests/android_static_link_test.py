#!/usr/bin/env python3
"""Exercise static libc, LTO, and compressed DWARF with the supplied host tools.

On x86_64, pass --runner qemu-aarch64 when testing an AArch64 toolchain.
Clang's child processes also require working binfmt, as in validate-ndk.sh.
Android executables are inspected, not run on the build host.
"""

import argparse
from pathlib import Path
import struct
import subprocess


MACHINES = {"armv7a": (1, 40), "aarch64": (2, 183), "i686": (1, 3),
            "x86_64": (2, 62), "riscv64": (2, 243)}


def elf(path):
    data = path.read_bytes()
    if data[:4] != b"\x7fELF" or data[4:7] not in (b"\x01\x01\x01", b"\x02\x01\x01"):
        raise ValueError(f"not a little-endian ELF: {path}")
    fmt = "<16sHHIIIIIHHHHHH" if data[4] == 1 else "<16sHHIQQQIHHHHHH"
    return data, struct.unpack_from(fmt, data)


def check_static(path, target):
    data, h = elf(path)
    elf_class, machine = MACHINES[target.split("-")[0]]
    if data[4] != elf_class or h[2] != machine or h[1] != 2 or not h[4]:
        raise ValueError(f"wrong target or not a static executable: {path}")
    kinds = [struct.unpack_from("<I", data, h[5] + i * h[9])[0]
             for i in range(h[10])]
    # Plain -static must have LOAD segments, with no interpreter or dynamic table.
    if 1 not in kinds or 2 in kinds or 3 in kinds:
        raise ValueError(f"missing LOAD or unexpected DYNAMIC/INTERP segment: {path}")


def check_compressed_debug(path, compression):
    data, h = elf(path)
    fmt = "<IIIIIIIIII" if data[4] == 1 else "<IIQQQQIIQQ"
    sections = [struct.unpack_from(fmt, data, h[6] + i * h[11])
                for i in range(h[12])]
    names = sections[h[13]]
    strings = data[names[4]:names[4] + names[5]]
    expected = {"zlib": 1, "zstd": 2}[compression]
    count = 0
    for section in sections:
        name = strings[section[0]:].split(b"\0", 1)[0]
        if name.startswith(b".debug_") and section[2] & 0x800:  # SHF_COMPRESSED
            actual = struct.unpack_from("<I", data, section[4])[0]
            if actual != expected:
                raise ValueError(f"wrong compression type {actual} in {path}: {name!r}")
            count += 1
    if not count:
        raise ValueError(f"no {compression}-compressed DWARF sections in {path}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runner", nargs="*", default=[])
    parser.add_argument("--targets", nargs="+", required=True)
    args = parser.parse_args()
    toolchain = args.toolchain.resolve()
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)

    def run(tool, *arguments):
        subprocess.run([*args.runner, str(toolchain / "bin" / tool),
                        *map(str, arguments)], check=True)

    def compile(target, *arguments):
        linker = [] if "-c" in arguments else [f"--ld-path={toolchain / 'bin/ld.lld'}"]
        run("clang", f"--target={target}", f"--sysroot={toolchain / 'sysroot'}",
            *linker, *arguments)

    source = output / "static.c"
    source.write_text('''#include <stdio.h>
#include <stdlib.h>
#include <string.h>

int main(void) {
    char *message = malloc(128);
    if (!message) return 1;
    strcpy(message, "Android static libc and compressed debug information");
    puts(message);
    free(message);
    return 0;
}
''')
    for target in dict.fromkeys([*args.targets, "aarch64-linux-android35"]):
        binary = output / f"static-{target}"
        compile(target, "-O0", "-static", source, "-o", binary)
        check_static(binary, target)
        print(f"static-libc-ok target={target}", flush=True)

    target = "aarch64-linux-android35"
    binary = output / "static-lto"
    compile(target, "-O3", "-flto", "-static", source, "-o", binary)
    check_static(binary, target)
    print("static-libc-lto-ok target=aarch64-linux-android35", flush=True)

    plain_object = output / "debug.o"
    compile(target, "-O0", "-g", "-c", source, "-o", plain_object)
    for compression in ("zlib", "zstd"):
        obj = output / f"debug-{compression}.o"
        binary = output / f"static-{compression}"
        run("llvm-objcopy", f"--compress-debug-sections={compression}", plain_object, obj)
        # A successful link of an uncompressed fixture would miss the original bug.
        check_compressed_debug(obj, compression)
        compile(target, "-static", obj, f"-Wl,--compress-debug-sections={compression}",
                "-o", binary)
        check_static(binary, target)
        check_compressed_debug(binary, compression)
        run("llvm-dwarfdump", "--verify", "--quiet", binary)
        print(f"compressed-dwarf-ok format={compression}", flush=True)


if __name__ == "__main__":
    main()
