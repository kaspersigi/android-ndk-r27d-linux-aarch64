#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_root="$project_root/sources/llvm-project"
source_dir="$source_root/compiler-rt"
build_dir="$project_root/build/compiler-rt-linux-aarch64"
install_dir="$project_root/out/compiler-rt-linux-aarch64"
reference_dir=${REFERENCE_NDK:-/mnt/develop/android-ndk-r27d}/toolchains/llvm/prebuilt/linux-x86_64/lib/clang/18/lib/x86_64-unknown-linux-gnu
toolchain_file="$project_root/cmake/linux-aarch64-toolchain.cmake"
compat_patch="$project_root/patches/compiler-rt-linux-aarch64.patch"
jobs=${JOBS:-$(nproc)}

for required in "$source_dir/CMakeLists.txt" "$reference_dir" "$compat_patch"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing compiler-rt build input: $required" >&2
        exit 1
    fi
done

if ! rg -q 'ALL_MEMPROF_SUPPORTED_ARCH.*ARM64' \
    "$source_dir/cmake/Modules/AllSupportedArchDefs.cmake"; then
    git -C "$source_root" apply "$compat_patch"
fi

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCOMPILER_RT_DEFAULT_TARGET_ONLY=ON \
    -DCOMPILER_RT_BUILD_BUILTINS=ON \
    -DCOMPILER_RT_BUILD_SANITIZERS=ON \
    -DCOMPILER_RT_BUILD_XRAY=ON \
    -DCOMPILER_RT_BUILD_LIBFUZZER=ON \
    -DCOMPILER_RT_BUILD_PROFILE=ON \
    -DCOMPILER_RT_BUILD_ORC=ON \
    -DCOMPILER_RT_INCLUDE_TESTS=OFF \
    -DSANITIZER_CXX_ABI=libstdc++ \
    -DLLVM_CMAKE_DIR="$source_root/llvm/cmake/modules"
cmake --build "$build_dir" --parallel "$jobs"

mkdir -p "$install_dir/lib/aarch64-unknown-linux-gnu"
while IFS= read -r name; do
    case "$name" in
        libclang_rt.hwasan_aliases.a)
            built_name=libclang_rt.hwasan-aarch64.a
            ;;
        libclang_rt.hwasan_aliases.a.syms)
            built_name=libclang_rt.hwasan-aarch64.a.syms
            ;;
        libclang_rt.hwasan_aliases.so)
            built_name=libclang_rt.hwasan-aarch64.so
            ;;
        libclang_rt.hwasan_aliases_cxx.a)
            built_name=libclang_rt.hwasan_cxx-aarch64.a
            ;;
        libclang_rt.hwasan_aliases_cxx.a.syms)
            built_name=libclang_rt.hwasan_cxx-aarch64.a.syms
            ;;
        *.a.syms)
            built_name=${name%.a.syms}-aarch64.a.syms
            ;;
        *.a)
            built_name=${name%.a}-aarch64.a
            ;;
        *.so)
            built_name=${name%.so}-aarch64.so
            ;;
        *.o)
            built_name=${name%.o}-aarch64.o
            ;;
        *)
            echo "Unknown compiler-rt reference file type: $name" >&2
            exit 1
            ;;
    esac
    source_file="$build_dir/lib/linux/$built_name"
    if [[ ! -f "$source_file" ]]; then
        echo "Missing AArch64 compiler-rt output for $name: $source_file" >&2
        exit 1
    fi
    install -m 0644 "$source_file" \
        "$install_dir/lib/aarch64-unknown-linux-gnu/$name"
done < <(find "$reference_dir" -maxdepth 1 -type f -printf '%f\n' | sort)

reference_count=$(find "$reference_dir" -maxdepth 1 -type f | wc -l)
installed_count=$(find "$install_dir/lib/aarch64-unknown-linux-gnu" \
    -maxdepth 1 -type f | wc -l)
if [[ "$installed_count" -ne "$reference_count" ]]; then
    echo "compiler-rt inventory mismatch: reference=$reference_count installed=$installed_count" >&2
    exit 1
fi

find "$install_dir/lib/aarch64-unknown-linux-gnu" -maxdepth 1 -type f \
    -name '*.so' -o -name '*.o' | sort | xargs file
