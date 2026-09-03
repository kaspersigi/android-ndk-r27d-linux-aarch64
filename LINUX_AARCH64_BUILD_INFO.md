# Linux AArch64 community build

This is an unofficial Linux AArch64 host build of Android NDK r27d
(`27.3.13750724`). The host tag is `linux-aarch64`; Android target ABI names,
including `arm64-v8a`, are unchanged. Android target headers, sysroot
libraries, Android compiler runtimes, and target libc++ are copied unchanged
from Google's official Linux x86_64 r27d archive.

Host LLVM/Clang is built from the exact revisions recorded by the official
archive:

- `toolchain/llvm-project`: `d8003a456d14a3deb8054cdaa529ffbf02d9b262`
- `toolchain/llvm_android`: `3503453cd6ccac933b4a1ec5255b7fc29851ea6b`
- Clang 18.0.4, based on `r522817d`

The package includes AArch64 builds of LLVM/Clang/LLD/LLDB/BOLT/Polly, bundled
CPython 3.11, GNU Make, Yasm, shaderc, SPIRV-Tools, glslang, host libc++,
compiler-rt, and `libsimpleperf_report.so`. The static Simpleperf executable is
Google's exact Android AArch64 r27d binary. This build does not reproduce
Google's PGO/BOLT/MLGO optimization pipeline and is not byte-for-byte identical
to an official NDK.

The normalized package inventory is one-for-one with the official Linux
x86_64 tree: 9,279 entries, with no missing paths, extra paths, type changes,
permission changes, or symlink-target changes after host-name normalization.
Validation covers Clang/LLD/LLDB/Python, shader tools, Simpleperf reporting,
direct C/C++ linking for all five r27d target architectures, CMake, ndk-build,
149 host ELF files, and 47 host static archives.

Compatibility boundaries:

- The host binaries require glibc 2.43 or newer.
- Upstream compiler-rt does not officially support Linux AArch64 MemProf or
  DD in this revision; those paths are experimental builds. The five
  x86_64-only `hwasan_aliases` paths contain the standard AArch64 HWASan
  implementation.
- The native Simpleperf report library is built without libdexfile, so it
  cannot extract DEX symbols itself.
- `musl/lib/libclang.so` is the glibc-hosted AArch64 libclang, not a
  musl-hosted build. The primary glibc toolchain does not use this copy.
