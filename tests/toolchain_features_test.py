#!/usr/bin/env python3
"""Check packaged tool behavior, not just --version or the file inventory.

Android outputs are compiled, linked and inspected; no device execution is
claimed. On x86_64, --runner qemu-aarch64 also requires binfmt for compiler
children (including those launched by the scan-build Perl script).
"""

import argparse
import lzma
import os
from pathlib import Path
import shutil
import subprocess


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--toolchain", required=True, type=Path)
    parser.add_argument("--output", required=True, type=Path)
    parser.add_argument("--runner", nargs="*", default=[])
    parser.add_argument("--checks", nargs="+", default=["android", "driver", "lldb", "analysis"],
                        choices=["android", "driver", "lldb", "analysis"])
    args = parser.parse_args()
    tc = args.toolchain.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ, LC_ALL="C", PATH=f"{tc / 'bin'}:{os.environ['PATH']}")
    target = ["--target=aarch64-linux-android35", f"--sysroot={tc / 'sysroot'}"]
    log = out / "commands.log"
    log.write_text("")

    def command(argv):
        result = subprocess.run(list(map(str, argv)), cwd=out, env=env,
                                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        with log.open("a") as stream:
            stream.write(f"$ {argv!r}\n{result.stdout}\n")
        if result.returncode:
            raise RuntimeError(f"command failed ({result.returncode}): {argv!r}\n{result.stdout}")
        return result.stdout

    def tool(name, *options):
        return command([*args.runner, tc / "bin" / name, *options])

    def compile(source, binary, *options, cxx=False):
        return tool("clang++" if cxx else "clang", *target,
                    f"--ld-path={tc / 'bin/ld.lld'}", source, *options, "-o", binary)

    def require(text, needle, context):
        if needle not in text:
            raise RuntimeError(f"{context}: missing {needle!r}; see {log}\n{text}")

    def passed(name):
        print(f"toolchain-feature-ok {name}", flush=True)

    source = out / "features.c"
    source.write_text("int main(int argc, char **argv) { return argv[argc-1][0] + argc; }\n")
    if "android" in args.checks:
        for sanitizer, symbol in (("hwaddress", "__hwasan_init"), ("address", "__asan_init"),
                                  ("undefined", "__ubsan_handle_add_overflow")):
            binary = out / f"sanitize-{sanitizer}"
            compile(source, binary, "-O0", "-g", f"-fsanitize={sanitizer}")
            require(tool("llvm-nm", binary), symbol, sanitizer)
            require(tool("llvm-readelf", "-h", binary), "AArch64", sanitizer)
            passed(f"android-{sanitizer}-link")

        omp = out / "openmp.c"
        omp.write_text('''#include <omp.h>
int main(void) {
    int sum = 0;
#pragma omp parallel reduction(+:sum)
    sum += omp_get_thread_num() + 1;
    return sum == 0;
}
''')
        binary = out / "openmp"
        compile(omp, binary, "-fopenmp")
        require(tool("llvm-nm", binary), "__kmpc_fork_call", "OpenMP")
        passed("android-openmp-link")

        binary = out / "profile"
        compile(source, binary, "-fprofile-instr-generate", "-fcoverage-mapping")
        require(tool("llvm-nm", binary), "__llvm_profile_write_file", "profile runtime")
        require(tool("llvm-readelf", "-S", binary), "__llvm_prf_cnts", "profile counters")
        passed("android-profile-link")

        cpp = out / "exceptions.cpp"
        cpp.write_text('''#include <stdexcept>
#include <string>
extern "C" int check_exception(int value) {
    try {
        if (value) throw std::runtime_error(std::string("ndk exception"));
    } catch (const std::exception& error) { return error.what()[0]; }
    return 0;
}
''')
        for linkage in ("shared", "static"):
            binary = out / f"libexceptions-{linkage}.so"
            options = ["-std=c++20", "-stdlib=libc++", "-fPIC", "-shared", "-O2", "-flto=thin"]
            if linkage == "static":
                options.append("-static-libstdc++")
            compile(cpp, binary, *options, cxx=True)
            dynamic = tool("llvm-readelf", "-d", binary)
            if ("[libc++_shared.so]" in dynamic) != (linkage == "shared"):
                raise RuntimeError(f"wrong libc++ linkage: {binary}\n{dynamic}")
            require(tool("llvm-nm", binary), "__cxa_throw", "C++ exceptions")
            passed(f"android-libcxx-{linkage}-exceptions-thinlto-link")

    if "driver" in args.checks:
        # -### checks the external assembler path without needing a target GNU as.
        trace = tool("clang", *target, "-###", "-fno-integrated-as", "-gsplit-dwarf", "-g",
                     "-c", source, "-o", out / "external.o")
        require(trace, str(tc / "bin/llvm-objcopy"), "external split DWARF driver")
        trace = tool("clang", *target, "-###", source, "-o", out / "default-linker")
        require(trace, str(tc / "bin/ld.lld"), "default Android linker")
        obj = out / "split.o"
        tool("clang", *target, "-gsplit-dwarf", "-g", "-c", source, "-o", obj)
        dwo = out / "split.dwo"
        if not dwo.is_file():
            raise RuntimeError("integrated assembler did not produce split.dwo")
        require(tool("llvm-readelf", "-S", dwo), ".debug_info.dwo", "split DWARF content")
        passed("driver-defaults-and-split-dwarf")

    if "lldb" in args.checks:
        mini = out / "minidebug.c"
        mini.write_text('''__attribute__((noinline)) static int ndk_minidebug_symbol(int n) {
    return n * 4;
}
int ndk_exported(int n) { return ndk_minidebug_symbol(n); }
''')
        original = out / "libminidebug.so"
        stripped = out / "libminidebug-stripped.so"
        debug = out / "minidebug.debug"
        compile(mini, original, "-O0", "-g", "-fPIC", "-shared")
        tool("llvm-objcopy", "--only-keep-debug", original, debug)
        tool("llvm-objcopy", "--strip-all", original, stripped)
        before = tool("lldb", "--no-lldbinit", "-b", "-o", "image dump symtab", stripped)
        if "ndk_minidebug_symbol" in before:
            raise RuntimeError("fixture still exposes the local symbol before adding .gnu_debugdata")
        packed = out / "minidebug.xz"
        packed.write_bytes(lzma.compress(debug.read_bytes(), format=lzma.FORMAT_XZ))
        tool("llvm-objcopy", "--add-section", f".gnu_debugdata={packed}", stripped)
        after = tool("lldb", "--no-lldbinit", "-b", "-o", "image dump symtab", stripped)
        require(after, "ndk_minidebug_symbol", "LLDB XZ-compressed MiniDebugInfo")
        if "No LZMA support" in after:
            raise RuntimeError("LLDB has no LZMA support")
        passed("lldb-minidebuginfo")

    if "analysis" in args.checks:
        bug = out / "null-deref.c"
        bug.write_text("int ndk_analyzer_bug(void) { int *pointer = 0; return *pointer; }\n")
        output = tool("clang-tidy", "--checks=-*,clang-analyzer-core.NullDereference",
                      bug, "--", *target)
        require(output, "clang-analyzer-core.NullDereference", "clang-tidy diagnosis")
        passed("clang-tidy-null-dereference")
        reports = out / "scan-build-reports"
        if reports.exists():
            shutil.rmtree(reports)
        # scan-build is a host Perl script; its analyzer and compiler must come
        # from this package. --override-compiler also guards against host CC.
        command([tc / "bin/scan-build", "--use-analyzer", tc / "bin/clang",
                 "--use-cc", tc / "bin/clang", "--override-compiler", "-plist",
                 "-o", reports, "clang", *target, "-c", bug, "-o", out / "analyzed.o"])
        import plistlib
        diagnostics = [d for report in reports.rglob("*.plist")
                       for d in plistlib.loads(report.read_bytes()).get("diagnostics", [])]
        if not any(d.get("check_name") == "core.NullDereference" for d in diagnostics):
            raise RuntimeError(f"scan-build did not report the expected checker; see {log}")
        passed("scan-build-null-dereference")


if __name__ == "__main__":
    main()
