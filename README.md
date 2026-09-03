# Android NDK r27d for Linux AArch64

This repository builds an **unofficial** Linux AArch64 host package of Android
NDK r27d (`27.3.13750724`). Google does not publish a Linux AArch64 package for
this NDK release.

The resulting NDK uses the host tag `linux-aarch64`. Android target ABI names
do not change: for example, the 64-bit ARM Android ABI is still `arm64-v8a`.

The package starts from Google's official Linux x86_64 r27d archive. Android
target headers, the sysroot, target libc++, and Android runtime libraries are
kept unchanged. Linux x86_64 host programs and libraries are replaced with
AArch64 builds, and host-selection scripts are adapted for `linux-aarch64`.

This is a community build. It is not produced, signed, or supported by Google,
and it is not byte-for-byte identical to an official NDK package.

## Quick start

The supported build environment is **Ubuntu 26.04 (Resolute) on x86_64**. The
build machine cross-compiles the Linux AArch64 host tools and runs validation
through QEMU.

Install the complete dependency set:

```bash
./scripts/resolute-install-deps.sh
```

Run a clean build:

```bash
CLEAN=1 ./scripts/resolute-local-build.sh
```

The unified build script fetches pinned sources, builds every host component,
assembles the NDK, runs the validation suite, and creates the release archive.
It exits without producing a successful result if any required validation
fails.

## Outputs

Successful builds create:

| Path | Description |
| --- | --- |
| `dist/android-ndk-r27d/` | Assembled Linux AArch64 NDK |
| `dist/android-ndk-r27d-linux.zip` | Distributable archive |
| `dist/android-ndk-r27d-linux.zip.sha256` | SHA-256 checksum |

The archive name intentionally matches Google's Linux naming pattern. It
extracts to `android-ndk-r27d/`; the AArch64 identity is represented by the
internal `linux-aarch64` host tag.

After extracting the archive on a compatible Linux AArch64 system:

```bash
export ANDROID_NDK_HOME=/path/to/android-ndk-r27d
"$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-aarch64/bin/clang" --version
```

The current host binaries require glibc 2.43 or newer.

## Official reference package

Assembly requires Google's official Linux x86_64 NDK r27d package as the
reference tree. The build script chooses it in this order:

1. `REFERENCE_NDK`, when explicitly set.
2. `/mnt/develop/android-ndk-r27d`, when it is a valid r27d installation.
3. A checksum-verified download cached below `.deps/`.

The expected official archive is:

```text
URL:    https://dl.google.com/android/repository/android-ndk-r27d-linux.zip
SHA256: 601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9
```

To use an existing reference package:

```bash
REFERENCE_NDK=/path/to/android-ndk-r27d \
  CLEAN=1 ./scripts/resolute-local-build.sh
```

## Build options

| Variable | Default | Purpose |
| --- | --- | --- |
| `CLEAN` | `0` | Set to `1` to remove `sources/`, `build/`, `out/`, and `dist/` before building |
| `JOBS` | `nproc` | Number of parallel build jobs |
| `REFERENCE_NDK` | auto-detected | Path to an extracted official Linux x86_64 r27d package |
| `REFERENCE_NDK_CACHE_DIR` | `.deps/` | Download and extraction cache for the official reference package |
| `REFERENCE_NDK_URL` | official URL | Override the reference archive URL |
| `REFERENCE_NDK_SHA256` | pinned checksum | Override the expected reference archive checksum |
| `ALLOW_UNSUPPORTED_HOST` | `0` | Set to `1` to bypass the Ubuntu 26.04 host check at your own risk |

`CLEAN=1` deliberately preserves `.deps/`, allowing the verified official
reference archive to be reused. To reduce parallelism without deleting the
current build trees:

```bash
JOBS=8 ./scripts/resolute-local-build.sh
```

## What is built

The Linux AArch64 host package includes builds of:

- LLVM, Clang, LLD, LLDB, BOLT, Polly, and Clang extra tools
- LLVM compiler runtimes and host libc++
- bundled CPython 3.11 with LLDB Python bindings
- GNU Make 4.3 and Yasm 1.3.0
- shaderc, glslang, and SPIRV-Tools
- Simpleperf report support
- the musl compatibility helper required by the reference layout

LLVM is built in two stages: native x86_64 table generators are created first,
then the toolchain is cross-compiled for `aarch64-unknown-linux-gnu`.

The compiler revisions match the revisions recorded in the official r27d
`BUILD_INFO`:

| Source | Revision |
| --- | --- |
| `toolchain/llvm-project` | `d8003a456d14a3deb8054cdaa529ffbf02d9b262` |
| `toolchain/llvm_android` | `3503453cd6ccac933b4a1ec5255b7fc29851ea6b` |
| Compiler identity | Clang 18.0.4, based on `r522817d` |

All other source revisions are also pinned in
[`scripts/fetch-sources.sh`](scripts/fetch-sources.sh). Compatibility and host
tag changes are maintained as reviewable files under [`patches/`](patches/).

## Validation

[`scripts/validate-ndk.sh`](scripts/validate-ndk.sh) runs natively on AArch64
or through QEMU on the supported x86_64 build host. It verifies:

- transparent AArch64 child-process execution through `qemu-user-binfmt`,
  which Clang needs to launch its own `clang-18` and `ld.lld` binaries;
- the normalized package inventory, entry types, permissions, and symlink
  targets against the official Linux x86_64 package;
- that Linux host ELF files and host archive members are AArch64;
- Clang, LLD, LLDB, BOLT, LLVM target registration, Python, and LLDB's Python
  bindings;
- GNU Make, Yasm, shader compilation, SPIR-V validation, and Simpleperf report
  processing;
- direct C and C++ linking for ARM, AArch64, x86, x86_64, and RISC-V Android
  targets;
- Android CMake toolchain integration for `arm64-v8a`;
- `ndk-build` output for `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64`.

The reference and candidate entry counts must match exactly. This is a
one-for-one layout check after host-name normalization, not a claim that rebuilt
host binaries are byte-identical to Google's x86_64 binaries.

## GitHub Actions release

[`release.yml`](.github/workflows/release.yml) runs a clean build on an Ubuntu
26.04 GitHub-hosted runner whenever a `v*` tag is pushed. The workflow:

1. installs dependencies with the same repository script;
2. builds, assembles, and validates the package;
3. uploads the ZIP and checksum as a one-day workflow artifact;
4. downloads and verifies both files in a separate publish job;
5. creates or updates the corresponding GitHub Release.

Example release tag:

```bash
git tag v1.0.0
git push origin v1.0.0
```

The published assets are:

```text
android-ndk-r27d-linux.zip
android-ndk-r27d-linux.zip.sha256
```

## Known limitations

- The host binaries require glibc 2.43 or newer.
- This project does not reproduce Google's PGO, BOLT, or MLGO optimization
  pipeline, so rebuilt host binaries differ in size, performance, and content.
- Linux AArch64 MemProf and deadlock-detector compiler runtimes are
  experimental in this source revision. Compatibility implementations are
  built to preserve the official file inventory.
- The five reference paths containing `hwasan_aliases` are x86_64-specific;
  those paths contain the normal AArch64 HWASan implementation in this package.
- Google's static Android AArch64 Simpleperf executable is reused. The native
  AArch64 `libsimpleperf_report.so` is built without libdexfile, so it cannot
  extract DEX symbols itself.
- `musl/lib/libclang.so` is an AArch64 glibc-hosted compatibility copy, not a
  musl-hosted build. The primary glibc toolchain does not use this copy.

See [`LINUX_AARCH64_BUILD_INFO.md`](LINUX_AARCH64_BUILD_INFO.md) for the
technical build boundary included with this repository.

## Component scripts

The unified entry point is the supported way to produce a release. Individual
component scripts remain available for development and troubleshooting, in
the following order:

```text
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
