# Official LLVM build configuration (r27d)

The official NDK provides enough information to recover version-specific
build inputs and explicitly selected options. Use those as the baseline for
feature support, with documented changes for the Linux AArch64 host.
This document records the inspected configuration and current differences;
it does not claim that every official option has already been ported.

## Provenance

The official Linux x86_64 NDK contains these files under
`toolchains/llvm/prebuilt/linux-x86_64/`:

- `BUILD_INFO`: build ID **13691557**, the build command in
  `target.rules`, and source revisions in `repo-dict`.
- `manifest_13691557.xml`: the pinned multi-repository source manifest.

The recorded `toolchain/llvm_android` revision is
[`3503453cd6ccac933b4a1ec5255b7fc29851ea6b`](https://android.googlesource.com/toolchain/llvm_android/+/3503453cd6ccac933b4a1ec5255b7fc29851ea6b/).
The relevant files at that revision are
[`base_builders.py`](https://android.googlesource.com/toolchain/llvm_android/+/3503453cd6ccac933b4a1ec5255b7fc29851ea6b/base_builders.py),
[`builders.py`](https://android.googlesource.com/toolchain/llvm_android/+/3503453cd6ccac933b4a1ec5255b7fc29851ea6b/builders.py),
[`configs.py`](https://android.googlesource.com/toolchain/llvm_android/+/3503453cd6ccac933b4a1ec5255b7fc29851ea6b/configs.py), and
[`do_build.py`](https://android.googlesource.com/toolchain/llvm_android/+/3503453cd6ccac933b4a1ec5255b7fc29851ea6b/do_build.py).

The recorded top-level build command is:

```text
DIST_DIR=%dist_dir% OUT_DIR=out prebuilts/python/linux-x86/bin/python3 toolchain/llvm_android/build.py --lto --pgo --bolt --mlgo --create-tar --no-build=windows --build-name %bid% --no-incremental
```

The shipped NDK does not contain the original stage2 `CMakeCache.txt` or
`cmake_invocation.sh`. The official build scripts generate the latter while
building. The settings below come from the pinned scripts and LLVM defaults,
not from a recovered original CMake cache.

## Feature settings

These refer to the shipped host toolchain, not the temporary native table
generators. See [`scripts/build-llvm.sh`](scripts/build-llvm.sh) for the current
cross-build arguments.

| Setting | Official Linux configuration | This AArch64 build |
| --- | --- | --- |
| `LLVM_TARGETS_TO_BUILD` | `AArch64;ARM;BPF;RISCV;WebAssembly;X86` | Same |
| `LLVM_ENABLE_PROJECTS` | `bolt;clang;clang-tools-extra;lld;lldb;polly` | Same |
| `LLVM_ENABLE_ASSERTIONS` | `OFF` | Same |
| `LLVM_ENABLE_TERMINFO` | `OFF` | Same |
| `LLVM_ENABLE_ZLIB` | LLVM default `ON` | `FORCE_ON`, explicit AArch64 static archive |
| `LLVM_ENABLE_ZSTD` | `FORCE_ON` | Same |
| `LLVM_USE_STATIC_ZSTD` | `ON` | Same |
| `LLDB_ENABLE_LZMA` | `ON`, with the XZ dependency | Same, explicit AArch64 static archive |
| `LLDB_ENABLE_PYTHON/LIBEDIT/LIBXML2/CURSES` | `ON` | Same |
| `LLDB_ENABLE_LUA` | `OFF` | Same |
| `LLDB_EMBED_PYTHON_HOME` | `OFF` | Same |
| `CLANG_DEFAULT_LINKER` | `lld` | Same |
| `CLANG_DEFAULT_OBJCOPY` | `llvm-objcopy` | Same |
| `LLVM_ENABLE_PLUGINS` | `OFF` | ON (an existing extension over the official configuration) |

`FORCE_ON` makes a missing compression dependency a configuration error.
The build explicitly supplies target headers and archives to avoid finding
x86_64 libraries while cross-compiling. Compression remains disabled only
for the temporary native table generators, which are not shipped.

The official LLVM dependency pins are:

| Source | Revision |
| --- | --- |
| `platform/external/zstd` | `38ed4f43b1c8a40559aebded780baa563dd10747` |
| `toolchain/xz` | `47426872d1366c32538a8e9c8f559b03cb45b648` |

XZ matches the official LLVM pin. This checkout currently shares Zstd
`bf5d66e5db49af979e080d4a030a02f07cf84ccb` with its Simpleperf build;
that is **not** the official LLVM Zstd pin above. The compression feature
settings match, but the dependency revisions are not yet identical. Changing
this source requires checking both LLVM and Simpleperf consumers.

## Host adaptations and remaining differences

The official Linux configuration uses an x86_64 host triple, sysroot,
bootstrap compiler and Python/dependency paths. The AArch64 build needs its
own triple, libraries, cross-compilation setup, Python extension suffixes and
runtime search paths. These values cannot be copied literally.

Other existing differences remain explicit:

- The official toolchain is built with host libc++ and
  `LLVM_STATIC_LINK_CXX_STDLIB=ON`. This cross-build links host libstdc++
  and libgcc statically. This concerns the LLVM executables themselves;
  Android applications still use the unchanged official target libc++.
- Official `LLVM_BUILD_LLVM_DYLIB=ON`; this build uses `OFF` and
  `LLVM_LINK_LLVM_DYLIB=OFF`. The official NDK packaging does not include
  `libLLVM.so`, so this build-time setting alone does not describe the
  shipped library inventory.
- The official command enables `--lto --pgo --bolt --mlgo`. This build
  does not reproduce that pipeline. Official `--lto` selects
  `LLVM_ENABLE_LTO=Thin` for building the compiler itself; it is separate
  from support for an application's `-flto`.
- PGO/BOLT need suitable profile inputs and MLGO needs model/build
  dependencies. Adopting them requires an AArch64-compatible implementation
  and validation, not only enabling CMake switches. MLGO can affect generated
  Android code and explicit LLVM options, so its absence is not solely a
  difference in host compiler speed.
- Official stage2 includes `compiler-rt;libcxx;libcxxabi;libunwind` as
  runtime projects. This repository has separate host runtime build steps
  and preserves the official Android runtime files.

Matching configuration is necessary but does not prove functional parity.
The packaging gate also runs static-libc/LTO, compressed DWARF,
MiniDebugInfo, sanitizer/OpenMP/profile linking, C++ exception, driver,
clang-tidy and scan-build checks. QEMU execution and link checks do not
replace native-host or Android-device validation.
