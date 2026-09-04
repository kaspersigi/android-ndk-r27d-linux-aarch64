#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$project_root/scripts/build-jobs.sh"
source_dir="$project_root/sources/llvm-project/runtimes"
build_dir="$project_root/build/host-runtimes-linux-aarch64"
install_dir="$project_root/out/host-runtimes-linux-aarch64"
toolchain_file="$project_root/cmake/linux-aarch64-toolchain.cmake"
jobs=$(resolve_build_jobs)
libatomic_archive=$(aarch64-linux-gnu-gcc -print-file-name=libatomic.a)

if [[ ! -f "$source_dir/CMakeLists.txt" ]]; then
    echo "Missing LLVM runtimes source tree: $source_dir" >&2
    exit 1
fi
if [[ ! -f "$libatomic_archive" ]]; then
    echo "Missing AArch64 static libatomic: $libatomic_archive" >&2
    exit 1
fi

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_ASM_COMPILER_EXTERNAL_TOOLCHAIN= \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DLLVM_ENABLE_RUNTIMES='libcxx;libcxxabi;libunwind' \
    -DLIBCXX_ENABLE_SHARED=ON \
    -DLIBCXX_ENABLE_STATIC=ON \
    -DLIBCXX_ENABLE_ABI_LINKER_SCRIPT=OFF \
    -DLIBCXX_ENABLE_STATIC_ABI_LIBRARY=ON \
    -DLIBCXX_CXX_ABI=libcxxabi \
    -DLIBCXXABI_ENABLE_SHARED=ON \
    -DLIBCXXABI_ENABLE_STATIC=ON \
    -DLIBCXXABI_USE_LLVM_UNWINDER=ON \
    -DLIBCXXABI_ENABLE_STATIC_UNWINDER=ON \
    -DLIBUNWIND_ENABLE_SHARED=ON \
    -DLIBUNWIND_ENABLE_STATIC=ON \
    -DCMAKE_PLATFORM_NO_VERSIONED_SONAME=ON \
    -DLIBCXX_HAS_ATOMIC_LIB=OFF \
    -DCMAKE_CXX_STANDARD_LIBRARIES="$libatomic_archive" \
    -DLIBCXX_INCLUDE_TESTS=OFF \
    -DLIBCXXABI_INCLUDE_TESTS=OFF \
    -DLIBUNWIND_INCLUDE_TESTS=OFF

cmake --build "$build_dir" --parallel "$jobs"
cmake --install "$build_dir"
find "$install_dir" -type f -name 'libc++*' -o -name 'libunwind*' \
    | sort | xargs file
