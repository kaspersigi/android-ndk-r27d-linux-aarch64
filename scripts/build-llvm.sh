#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$project_root/sources/llvm-project/llvm"
native_build_dir="$project_root/build/llvm-native-tools-clang"
cross_build_dir="$project_root/build/llvm-linux-aarch64"
bolt_runtime_build_dir="$project_root/build/bolt-runtime-linux-aarch64"
install_dir="$project_root/out/llvm-linux-aarch64"
toolchain_file="$project_root/cmake/linux-aarch64-toolchain.cmake"
host_deps="$project_root/out/host-deps-linux-aarch64"
target_python="$project_root/out/python-linux-aarch64"
build_python="$project_root/sources/python-prebuilt-reference/bin/python3.11"
swig="$project_root/out/swig-linux-x86_64/bin/swig"
jobs=${JOBS:-$(nproc)}
smallvector_patch="$project_root/patches/llvm-smallvector-include-cstdint.patch"
x86_mctargetdesc_patch="$project_root/patches/llvm-x86-mctargetdesc-include-cstdint.patch"
lldb_addressable_bits_patch="$project_root/patches/lldb-addressable-bits-include-cstdint.patch"
lldb_unversioned_patch="$project_root/patches/lldb-unversioned-shared-library.patch"

if [[ ! -f "$source_dir/CMakeLists.txt" ]]; then
    echo "Missing LLVM source tree: $source_dir" >&2
    exit 1
fi

for required in \
    "$host_deps/lib/libedit.so" \
    "$host_deps/lib/libncurses.so" \
    "$host_deps/lib/libpanel.so" \
    "$host_deps/lib/libxml2.so" \
    "$target_python/include/python3.11/Python.h" \
    "$target_python/lib/libpython3.11.so" \
    "$build_python" \
    "$swig"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing LLVM/LLDB build input: $required" >&2
        exit 1
    fi
done

if ! rg -q '^#include <cstdint>$' \
    "$project_root/sources/llvm-project/llvm/include/llvm/ADT/SmallVector.h"; then
    git -C "$project_root/sources/llvm-project" apply "$smallvector_patch"
fi

if ! rg -q '^#include <cstdint>$' \
    "$project_root/sources/llvm-project/llvm/lib/Target/X86/MCTargetDesc/X86MCTargetDesc.h"; then
    git -C "$project_root/sources/llvm-project" apply "$x86_mctargetdesc_patch"
fi

if ! rg -q '^#include <cstdint>$' \
    "$project_root/sources/llvm-project/lldb/include/lldb/Utility/AddressableBits.h"; then
    git -C "$project_root/sources/llvm-project" apply "$lldb_addressable_bits_patch"
fi

if ! rg -q 'Android.s NDK exposes its LLDB shared objects' \
    "$project_root/sources/llvm-project/llvm/cmake/modules/AddLLVM.cmake"; then
    git -C "$project_root/sources/llvm-project" apply "$lldb_unversioned_patch"
fi

common_options=(
    -G Ninja
    -DCMAKE_BUILD_TYPE=Release
    -DLLVM_TARGETS_TO_BUILD=AArch64\;ARM\;BPF\;RISCV\;WebAssembly\;X86
    -DLLVM_ENABLE_ASSERTIONS=OFF
    -DLLVM_ENABLE_BINDINGS=OFF
    -DLLVM_ENABLE_DIA_SDK=OFF
    -DLLVM_ENABLE_FFI=OFF
    -DLLVM_ENABLE_PLUGINS=ON
    -DLLVM_ENABLE_TERMINFO=OFF
    -DLLVM_ENABLE_Z3_SOLVER=OFF
    -DLLVM_ENABLE_ZLIB=OFF
    -DLLVM_ENABLE_ZSTD=OFF
    -DLLVM_INCLUDE_BENCHMARKS=OFF
    -DLLVM_INCLUDE_EXAMPLES=OFF
    -DLLVM_INCLUDE_TESTS=OFF
    -DCLANG_INCLUDE_TESTS=OFF
    -DLLD_INCLUDE_TESTS=OFF
    -DPOLLY_INCLUDE_TESTS=OFF
    -DLLVM_VERSION_PATCH=4
    -DLLVM_VERSION_SUFFIX=
    -DCLANG_REPOSITORY_STRING=https://android.googlesource.com/toolchain/llvm-project
    -DBUG_REPORT_URL=https://github.com/android-ndk/ndk/issues
)

cmake -S "$source_dir" -B "$native_build_dir" \
    "${common_options[@]}" \
    -DLLVM_ENABLE_PROJECTS=bolt\;clang\;clang-tools-extra\;lld\;polly \
    -DCMAKE_C_COMPILER=clang \
    -DCMAKE_CXX_COMPILER=clang++
cmake --build "$native_build_dir" --parallel "$jobs" \
    --target llvm-tblgen clang-tblgen

cmake -S "$source_dir" -B "$cross_build_dir" \
    "${common_options[@]}" \
    -DLLVM_ENABLE_PROJECTS=bolt\;clang\;clang-tools-extra\;lld\;lldb\;polly \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCMAKE_PREFIX_PATH="$host_deps;$target_python" \
    -DCMAKE_BUILD_RPATH="$host_deps/lib;$target_python/lib" \
    -DCMAKE_INSTALL_RPATH='$ORIGIN/../lib;$ORIGIN/../python3/lib' \
    -DCMAKE_EXE_LINKER_FLAGS=-static-libgcc\ -static-libstdc++ \
    -DCMAKE_SHARED_LINKER_FLAGS=-static-libgcc\ -static-libstdc++ \
    -DCMAKE_MODULE_LINKER_FLAGS=-static-libgcc\ -static-libstdc++ \
    -DCLANG_VENDOR=Android\ \(Linux\ AArch64\ community\ build\ based\ on\ r522817d\) \
    -DLLVM_BUILD_LLVM_DYLIB=OFF \
    -DLLVM_DEFAULT_TARGET_TRIPLE=aarch64-unknown-linux-gnu \
    -DLLVM_HOST_TRIPLE=aarch64-unknown-linux-gnu \
    -DLLVM_ENABLE_LIBXML2=ON \
    -DLLVM_LINK_LLVM_DYLIB=OFF \
    -DLLVM_NATIVE_TOOL_DIR="$native_build_dir/bin" \
    -DLLDB_ENABLE_LUA=OFF \
    -DLLDB_ENABLE_PYTHON=ON \
    -DLLDB_EMBED_PYTHON_HOME=OFF \
    -DLLDB_ENABLE_LZMA=OFF \
    -DLLDB_ENABLE_LIBEDIT=ON \
    -DLLDB_ENABLE_LIBXML2=ON \
    -DLLDB_ENABLE_CURSES=ON \
    -DLLDB_INCLUDE_TESTS=OFF \
    -DLLDB_PYTHON_RELATIVE_PATH=lib/python3.11/site-packages \
    -DLLDB_PYTHON_EXE_RELATIVE_PATH=python3 \
    -DLLDB_PYTHON_EXT_SUFFIX=.cpython-311-aarch64-linux-gnu.so \
    -DSWIG_EXECUTABLE="$swig" \
    -DPython3_EXECUTABLE="$build_python" \
    -DPython3_INCLUDE_DIR="$target_python/include/python3.11" \
    -DPython3_INCLUDE_DIRS="$target_python/include/python3.11" \
    -DPython3_LIBRARY="$target_python/lib/libpython3.11.so" \
    -DPython3_LIBRARIES="$target_python/lib/libpython3.11.so" \
    -DLibEdit_INCLUDE_DIRS="$host_deps/include" \
    -DLibEdit_LIBRARIES="$host_deps/lib/libedit.so" \
    -DLIBXML2_INCLUDE_DIR="$host_deps/include/libxml2" \
    -DLIBXML2_LIBRARY="$host_deps/lib/libxml2.so" \
    -DCURSES_INCLUDE_DIRS="$host_deps/include;$host_deps/include/ncurses" \
    -DCURSES_LIBRARIES="$host_deps/lib/libncurses.so;$host_deps/lib/libform.so;$host_deps/lib/libpanel.so" \
    -DPANEL_LIBRARIES="$host_deps/lib/libpanel.so"

cmake --build "$cross_build_dir" --parallel "$jobs"
cmake --install "$cross_build_dir"

# BOLT disables its runtime automatically while cross-compiling. Build the
# freestanding runtime separately so llvm-bolt can instrument AArch64 hosts.
cmake -S "$project_root/sources/llvm-project/bolt/runtime" \
    -B "$bolt_runtime_build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DLLVM_LIBRARY_DIR="$bolt_runtime_build_dir/lib"
cmake --build "$bolt_runtime_build_dir" --parallel "$jobs"
cmake --install "$bolt_runtime_build_dir"
