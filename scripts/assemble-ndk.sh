#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
reference_ndk=${REFERENCE_NDK:-/mnt/develop/android-ndk-r27d}
llvm_install="$project_root/out/llvm-linux-aarch64"
host_runtimes="$project_root/out/host-runtimes-linux-aarch64"
host_deps="$project_root/out/host-deps-linux-aarch64"
python_install="$project_root/out/python-linux-aarch64"
host_tools_install="$project_root/out/host-tools-linux-aarch64"
shader_tools_install="$project_root/out/shader-tools-linux-aarch64"
compiler_rt_install="$project_root/out/compiler-rt-linux-aarch64"
simpleperf_prebuilt="$project_root/sources/simpleperf-prebuilt"
simpleperf_host="$project_root/out/simpleperf-linux-aarch64"
musl_install="$project_root/out/musl-linux-aarch64"
dist_dir="$project_root/dist"
destination=${DESTINATION_NDK:-$dist_dir/android-ndk-r27d}
host_patch="$project_root/patches/ndk-linux-aarch64-host-tag.patch"

for required in \
    "$reference_ndk/source.properties" \
    "$llvm_install/bin/clang" \
    "$llvm_install/bin/lldb" \
    "$llvm_install/lib/liblldb.so" \
    "$llvm_install/lib/libbolt_rt_instr.a" \
    "$host_runtimes/lib/libc++.so" \
    "$python_install/bin/python3.11" \
    "$host_tools_install/bin/make" \
    "$host_tools_install/bin/yasm" \
    "$shader_tools_install/bin/glslc" \
    "$compiler_rt_install/lib/aarch64-unknown-linux-gnu/libclang_rt.builtins.a" \
    "$simpleperf_prebuilt/bin/android/arm64/simpleperf" \
    "$simpleperf_host/libsimpleperf_report.so" \
    "$simpleperf_host/libsimpleperf_readelf.a" \
    "$musl_install/lib/libc_musl.so" \
    "$host_patch"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing assembly input: $required" >&2
        exit 1
    fi
done

if [[ -e "$destination" ]]; then
    echo "Destination already exists: $destination" >&2
    exit 1
fi

mkdir -p "$dist_dir"
temporary_root=$(mktemp -d "$dist_dir/.android-ndk-r27d.XXXXXX")
package_root="$temporary_root/android-ndk-r27d"
cleanup() {
    if [[ -n "${temporary_root:-}" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}
trap cleanup EXIT

# Begin with the complete official tree. Rename only host-specific axes, then
# replace every x86_64 host object. This guarantees that target data and every
# architecture-independent file remain present one-for-one.
cp -a "$reference_ndk" "$package_root"
mv "$package_root/prebuilt/linux-x86_64" \
    "$package_root/prebuilt/linux-aarch64"
mv "$package_root/shader-tools/linux-x86_64" \
    "$package_root/shader-tools/linux-aarch64"
mv "$package_root/simpleperf/bin/linux/x86_64" \
    "$package_root/simpleperf/bin/linux/aarch64"
mv "$package_root/toolchains/llvm/prebuilt/linux-x86_64" \
    "$package_root/toolchains/llvm/prebuilt/linux-aarch64"

toolchain="$package_root/toolchains/llvm/prebuilt/linux-aarch64"
mv "$toolchain/lib/x86_64-unknown-linux-gnu" \
    "$toolchain/lib/aarch64-unknown-linux-gnu"
mv "$toolchain/lib/clang/18/lib/x86_64-unknown-linux-gnu" \
    "$toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu"

# Normalize CPython ABI-bearing path names from x86_64 to AArch64.
while IFS= read -r -d '' old_path; do
    new_path=${old_path//x86_64-linux-gnu/aarch64-linux-gnu}
    mv "$old_path" "$new_path"
done < <(find "$toolchain/python3" -depth -name '*x86_64-linux-gnu*' -print0)
while IFS= read -r -d '' old_path; do
    new_path=${old_path//x86_64-linux-gnu/aarch64-linux-gnu}
    mv "$old_path" "$new_path"
done < <(find "$toolchain/lib/python3.11" -depth -name '*x86_64-linux-gnu*' -print0)

copy_regular() {
    local source=$1
    local target=$2
    local target_mode
    if [[ ! -e "$source" ]]; then
        echo "Missing AArch64 replacement for $target: $source" >&2
        exit 1
    fi
    target_mode=$(stat -c '%a' "$target")
    cp -L --preserve=timestamps "$source" "$target"
    chmod "$target_mode" "$target"
}

# Replace the complete official host executable inventory, preserving regular
# file versus symlink types from the reference package.
while IFS= read -r -d '' target; do
    if file -b "$target" | rg -q 'ELF 64-bit.*x86-64'; then
        name=$(basename "$target")
        if [[ "$name" == yasm ]]; then
            source="$host_tools_install/bin/yasm"
        else
            source="$llvm_install/bin/$name"
        fi
        copy_regular "$source" "$target"
    fi
done < <(find "$toolchain/bin" -maxdepth 1 -type f -print0)

# Replace host shared libraries using the LLVM build or its exact pinned
# dependency builds. The package deliberately keeps Google's SONAME filenames.
while IFS= read -r -d '' target; do
    if file -b "$target" | rg -q 'ELF 64-bit.*x86-64'; then
        name=$(basename "$target")
        if [[ -e "$llvm_install/lib/$name" ]]; then
            source="$llvm_install/lib/$name"
        elif [[ -e "$host_deps/lib/$name" ]]; then
            source="$host_deps/lib/$name"
        else
            echo "No AArch64 host-library replacement for $target" >&2
            exit 1
        fi
        copy_regular "$source" "$target"
    fi
done < <(find "$toolchain/lib" -maxdepth 1 -type f -print0)

# Replace the mapped GNU/Linux host runtimes. Other runtime directories are
# cross-target artifacts and remain byte-for-byte identical to the reference.
runtime_dir="$toolchain/lib/aarch64-unknown-linux-gnu"
for name in libc++.a libc++.so libc++abi.a libc++abi.so libc++experimental.a libunwind.a libunwind.so; do
    source="$host_runtimes/lib/$name"
    copy_regular "$source" "$runtime_dir/$name"
done
copy_regular "$simpleperf_host/libsimpleperf_readelf.a" \
    "$runtime_dir/libsimpleperf_readelf.a"
copy_regular "$llvm_install/lib/libbolt_rt_instr.a" \
    "$toolchain/lib/libbolt_rt_instr.a"

# Replace the complete compiler-rt inventory. Some runtime paths are normally
# omitted by upstream on AArch64, but the build script supplies AArch64
# compatibility implementations so the official r27d layout stays exact.
compiler_rt_dir="$toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu"
while IFS= read -r -d '' target; do
    copy_regular \
        "$compiler_rt_install/lib/aarch64-unknown-linux-gnu/$(basename "$target")" \
        "$target"
done < <(find "$compiler_rt_dir" -maxdepth 1 -type f -print0)

# These two files are host-side helpers even though they live below the musl
# target tree. libc_musl is built from the pinned AOSP musl revision. The
# libclang replacement is the AArch64 libclang from the same r27d LLVM build;
# the package's primary Linux host is glibc.
copy_regular "$musl_install/lib/libc_musl.so" \
    "$toolchain/musl/lib/libc_musl.so"
copy_regular "$llvm_install/lib/libclang.so" \
    "$toolchain/musl/lib/libclang.so"

# Rewrite host-runtime symlinks without changing their inventory or type.
while IFS= read -r -d '' link; do
    target=$(readlink "$link")
    mapped=${target//x86_64-unknown-linux-gnu/aarch64-unknown-linux-gnu}
    if [[ "$mapped" != "$target" ]]; then
        ln -sfn "$mapped" "$link"
    fi
done < <(find "$toolchain/lib" -maxdepth 1 -type l -print0)

# Replace all architecture-specific files in the exact CPython inventory.
while IFS= read -r -d '' target; do
    if file -b "$target" | rg -q 'ELF 64-bit.*x86-64'; then
        relative=${target#"$toolchain/python3/"}
        copy_regular "$python_install/$relative" "$target"
    fi
done < <(find "$toolchain/python3" -type f -print0)
for relative in \
    include/python3.11/pyconfig.h \
    lib/pkgconfig/python-3.11.pc \
    lib/pkgconfig/python-3.11-embed.pc \
    lib/python3.11/_sysconfigdata__linux_aarch64-linux-gnu.py; do
    copy_regular "$python_install/$relative" "$toolchain/python3/$relative"
done

# LLDB's generated Python package is installed separately from CPython.
lldb_python="$toolchain/lib/python3.11/site-packages/lldb"
while IFS= read -r -d '' target; do
    relative=${target#"$lldb_python/"}
    source="$llvm_install/lib/python3.11/site-packages/lldb/$relative"
    if [[ -L "$target" ]]; then
        link_target=$(readlink "$source")
        link_target=${link_target//x86_64-linux-gnu/aarch64-linux-gnu}
        ln -sfn "$link_target" "$target"
    else
        copy_regular "$source" "$target"
    fi
done < <(find "$lldb_python" \( -type f -o -type l \) -print0)

# GNU Make/Yasm host prebuilt: keep official headers and manuals, replace only
# architecture-dependent executables and the static library.
host_prebuilt="$package_root/prebuilt/linux-aarch64"
for name in make yasm vsyasm ytasm; do
    copy_regular "$host_tools_install/bin/$name" "$host_prebuilt/bin/$name"
done
copy_regular "$host_tools_install/lib/libyasm.a" "$host_prebuilt/lib/libyasm.a"

shader_tools="$package_root/shader-tools/linux-aarch64"
for name in glslc spirv-as spirv-cfg spirv-dis spirv-link spirv-opt spirv-reduce spirv-val; do
    copy_regular "$shader_tools_install/bin/$name" "$shader_tools/$name"
done
ln -sfn ../../toolchains/llvm/prebuilt/linux-aarch64/lib/libc++.so \
    "$shader_tools/libc++.so"

# The exact r27d Android AArch64 Simpleperf executable is static and runs as a
# Linux AArch64 process. Its report library is a native glibc AArch64 build.
simpleperf_dir="$package_root/simpleperf/bin/linux/aarch64"
copy_regular "$simpleperf_prebuilt/bin/android/arm64/simpleperf" \
    "$simpleperf_dir/simpleperf"
copy_regular "$simpleperf_host/libsimpleperf_report.so" \
    "$simpleperf_dir/libsimpleperf_report.so"

for patch_target in \
    build/tools/ndk_bin_common.sh \
    build/ndk-build \
    build/cmake/android.toolchain.cmake \
    build/cmake/android-legacy.toolchain.cmake \
    build/tools/make_standalone_toolchain.py \
    ndk-gdb ndk-lldb ndk-stack ndk-which; do
    chmod u+w "$package_root/$patch_target"
done
patch --batch --forward --no-backup-if-mismatch -p1 -d "$package_root" \
    < "$host_patch"

"$project_root/scripts/compare-reference-layout.py" "$package_root" \
    --reference "$reference_ndk"

mv "$package_root" "$destination"
rmdir "$temporary_root"
temporary_root=
trap - EXIT
echo "$destination"
