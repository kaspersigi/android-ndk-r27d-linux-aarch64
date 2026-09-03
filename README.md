# Android NDK r27d for Linux AArch64

This project builds an unofficial native Linux AArch64 host package for Android
NDK r27d. The target sysroot and Android runtime libraries are taken unchanged
from the official Linux x86_64 r27d package. Architecture-independent scripts
are preserved, while the Linux host executables and libraries are AArch64.
The host tag and package name are `linux-aarch64`; Android's target ABI name
remains `arm64-v8a`.

The compiler source revisions are pinned to the official r27d `BUILD_INFO`:

- `toolchain/llvm-project`: `d8003a456d14a3deb8054cdaa529ffbf02d9b262`
- `toolchain/llvm_android`: `3503453cd6ccac933b4a1ec5255b7fc29851ea6b`
- compiler identity: clang 18.0.4, based on `r522817d`

The first build stage creates native x86_64 table generators. The second stage
cross-compiles Clang, LLD, LLVM BOLT, LLVM utilities, Clang extra tools, and
Polly for `aarch64-unknown-linux-gnu`.

The patches under `patches/` contain the reproducible host-tag changes and the
small source/build-system compatibility changes needed by the AArch64 cross
build. The `include-cstdint` patches only compensate for modern C++ standard
libraries no longer exposing fixed-width integer typedefs transitively.

The glslang compatibility patch has the same purpose for `SpvBuilder.h`.

## Requirements

The build uses the official x86_64 NDK at
`/mnt/develop/android-ndk-r27d` as the target-data reference. Override that
path for assembly with `REFERENCE_NDK=/path/to/android-ndk-r27d`.

On Ubuntu/Debian, the required tools include:

```text
clang cmake ninja-build build-essential python3 ripgrep rsync file patch git zip
gcc-aarch64-linux-gnu g++-aarch64-linux-gnu qemu-user
```

## Build and validation

```bash
scripts/fetch-sources.sh
scripts/build-host-dependencies.sh
scripts/build-host-runtimes.sh
scripts/build-python.sh
scripts/build-swig.sh
scripts/build-llvm.sh
scripts/build-compiler-rt.sh
scripts/build-host-tools.sh
scripts/build-shader-tools.sh
scripts/build-simpleperf-readelf.sh
scripts/build-simpleperf-report.sh
scripts/build-host-musl.sh
scripts/assemble-ndk.sh
scripts/validate-ndk.sh
scripts/package-ndk.sh
```

The assembled package is written to `dist/android-ndk-r27d`, and the final
archive is `dist/android-ndk-r27d-linux.zip`. The archive's top-level directory
is `android-ndk-r27d/`. `validate-ndk.sh` runs natively on an
AArch64 host or through QEMU on an x86_64 build host. It checks host tools,
shader compilation, bundled Python and LLDB, host Simpleperf, C and C++ linking
for all r27d target architectures, CMake, ndk-build, the normalized one-for-one
reference layout (including permissions), the host ELF architecture boundary,
and all AArch64 host archive members. The reference and candidate both contain
9,279 normalized entries.

`build-host-tools.sh` builds GNU Make 4.3 and Yasm 1.3.0. The shader build uses
the exact `ndk-r27d` source revisions. The reference r27d package identifies
that unchanged shader tool set as `ndk-r26c`, so the AArch64 binaries preserve
the same version identity.

## Compatibility boundary

The current host binaries require glibc 2.43 or newer because they were linked
against the AArch64 cross sysroot installed on the build machine. The package
includes AArch64 builds of host LLDB, its bundled CPython 3.11 runtime, and the
Simpleperf report library.

Google's r27d compiler-rt sources do not normally publish Linux AArch64
MemProf or deadlock-detector runtimes. This build enables them experimentally
to retain the reference inventory. The five `hwasan_aliases` filenames are
x86_64-specific upstream; on AArch64 those exact paths contain the normal
AArch64 HWASan implementation. They are layout-compatible additions, not a
claim of upstream support or production qualification.

The Simpleperf executable is Google's static Android AArch64 r27d binary,
which is usable as a Linux AArch64 process. `libsimpleperf_report.so` is built
as a native glibc AArch64 library and passes the official `perf.data` report
test (2,409 samples). It is built without libdexfile, so report-library DEX
symbol extraction is unavailable.

The reference package also contains a musl-hosted `musl/lib/libclang.so`.
This project currently fills that exact path with the glibc-hosted AArch64
libclang from the main toolchain build. It has the correct host architecture
and keeps the reference layout exact, but it is not a musl-hosted libclang.
The primary `linux-aarch64` glibc toolchain does not use that compatibility
copy.
