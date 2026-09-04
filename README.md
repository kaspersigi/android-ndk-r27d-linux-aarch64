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

Host `libc++.so`, `libc++abi.so`, and `libunwind.so` incorporate their LLVM
ABI, unwinder, and atomic support without relying on unpackaged shared
libraries. Validation checks every host ELF: each non-glibc dependency must be
provided by a SONAME inside the NDK. Compiler-rt shared runtimes statically
incorporate libstdc++; their remaining `libgcc_s.so.1` dependency matches the
official Linux x86_64 NDK. The exact deprecated Python `nis` extension retains
the official-compatible libc6 `libnsl.so.1` dependency.

## Repository dependencies

This repository is an independently buildable producer of the NDK archive.
It does not depend on the Android SDK assembly repository.

- Its upstream binary reference is Google's checksum-pinned
  `android-ndk-r27d-linux.zip`. Architecture-independent Android target files
  are retained from that package, while Linux host tools are rebuilt for
  AArch64 from pinned upstream sources.
- Its release output, `android-ndk-r27d-linux.zip`, is a downstream input of
  [`kaspersigi/android-sdk-linux-aarch64`](https://github.com/kaspersigi/android-sdk-linux-aarch64).
  The SDK installs it as `ndk/27.3.13750724` without rebuilding the NDK.
- The SDK resolves this repository's latest published full GitHub Release and
  verifies the ZIP against the `.sha256` asset from that same Release. Local
  builds and source commits without a published Release are not selected.
- Release tags such as `v1.0.1` identify revisions of this repository's build
  scripts. They do not change the locked NDK source version, which remains
  r27d (`27.3.13750724`).

After changing this project, publish and validate a new NDK Release first. The
next SDK build selects it automatically as the latest Release; no SDK source
change is needed unless the repository, asset name, or NDK source version
changes.

## Official reference package

Assembly requires Google's official Linux x86_64 NDK r27d package as the
reference tree. By default, the build script verifies the pinned archive and
freshly extracts it for every build. This prevents generated files in a reused
directory from changing the package inventory.

An existing extracted tree is used only when `REFERENCE_NDK` is explicitly
set. It must have the exact 9,276-entry official layout and must not contain
generated Python bytecode. The comparison tool independently requires all four
official `linux-x86_64` host roots, rejects AArch64 host roots, and rejects a
candidate directory passed as its own reference.

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
| `JOBS` | unset | CI-only parallel job limit; local builds are fixed to `nproc` |
| `REFERENCE_NDK` | unset | Explicit path to an exact, clean official Linux x86_64 r27d package |
| `REFERENCE_NDK_CACHE_DIR` | `.deps/` | Download and extraction cache for the official reference package |
| `REFERENCE_NDK_URL` | official URL | Override the reference archive URL |
| `REFERENCE_NDK_SHA256` | pinned checksum | Override the expected reference archive checksum |
| `ALLOW_UNSUPPORTED_HOST` | `0` | Set to `1` to bypass the Ubuntu 26.04 host check at your own risk |

`CLEAN=1` deliberately preserves `.deps/`, allowing the verified official
reference archive to be reused.

Project policy requires every parallel-safe local build stage to use all
processors reported by `nproc`. Do not set `JOBS=4` locally to imitate the
hosted workflow: an NDK rebuild can otherwise waste hours. The build entry
rejects a smaller local `JOBS` value. `JOBS` is reserved for CI, and GitHub
Actions explicitly sets `JOBS=4` for the free hosted runner. The one deliberate
exception is the pinned SWIG autotools/Bison stage: it remains serial because
parallel make races `config.status` and `parser.h`; this small prerequisite does
not reduce parallelism for LLVM or the other long-running compilation stages.

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
- the normalized package inventory, entry types, permissions, symlink targets,
  and architecture-independent file contents against the official Linux
  x86_64 package;
- that Linux host ELF files and host archive members are AArch64;
- host C++ runtime SONAMEs, direct loadability, and every host ELF's
  shared-library dependency closure, plus compiler-rt's rejection of an
  external `libstdc++.so`;
- Clang, LLD, LLDB, BOLT, LLVM target registration, Python, and LLDB's Python
  bindings;
- GNU Make, Yasm, shader compilation, SPIR-V validation, and Simpleperf report
  processing, including legacy and Rust v0 symbol demangling;
- direct C and C++ linking for ARM, AArch64, x86, x86_64, and RISC-V Android
  targets;
- Android CMake toolchain integration for `arm64-v8a`;
- `ndk-build` output for `armeabi-v7a`, `arm64-v8a`, `x86`, and `x86_64`.

The reference must contain the fixed 9,276-entry r27d inventory, and the
candidate count must match it exactly. After host-name normalization, ordinary
files are SHA-256 checked. Only the documented patched/generated files and
actual x86_64-to-AArch64 ELF replacements may differ; rebuilt host binaries are
not expected to be byte-identical to Google's x86_64 binaries.

## GitHub Actions release

[`release.yml`](.github/workflows/release.yml) runs a clean build on an Ubuntu
26.04 GitHub-hosted runner whenever a `v*` tag is pushed. The workflow:

1. installs dependencies with the same repository script;
2. builds, assembles, and validates the package;
3. verifies that extracting the ZIP reproduces the assembled tree exactly;
4. uploads the ZIP and checksum as a one-day workflow artifact;
5. downloads and verifies both files in a separate publish job;
6. creates or updates the corresponding GitHub Release.

Example release tag (choose a new repository release version):

```bash
git tag vX.Y.Z
git push origin vX.Y.Z
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

## License

Repository-owned code is licensed under the Apache License 2.0; see
[`LICENSE`](LICENSE) and [`NOTICE`](NOTICE). Upstream components retain their
original licenses and notices in their corresponding source and package paths.

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
