#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$project_root/scripts/build-jobs.sh"
source_dir="$project_root/sources/shaderc"
build_dir="$project_root/build/shader-tools-linux-aarch64"
install_dir="$project_root/out/shader-tools-linux-aarch64"
toolchain_file="$project_root/cmake/linux-aarch64-toolchain.cmake"
jobs=$(resolve_build_jobs)
compatibility_patch="$project_root/patches/glslang-spvbuilder-include-cstdint.patch"
shaderc_tag_patch="$project_root/patches/shaderc-build-tag-override.patch"
spirv_tools_tag_patch="$project_root/patches/spirv-tools-build-tag-override.patch"

for source_path in \
    "$source_dir/CMakeLists.txt" \
    "$source_dir/third_party/glslang/CMakeLists.txt" \
    "$source_dir/third_party/spirv-tools/CMakeLists.txt" \
    "$source_dir/third_party/spirv-headers/CMakeLists.txt"; do
    if [[ ! -f "$source_path" ]]; then
        echo "Missing shader-tools source: $source_path" >&2
        exit 1
    fi
done

if ! rg -q '^#include <cstdint>$' \
    "$source_dir/third_party/glslang/SPIRV/SpvBuilder.h"; then
    git -C "$source_dir/third_party/glslang" apply "$compatibility_patch"
fi
if ! rg -q 'NDK_BUILD_TAG' "$source_dir/utils/update_build_version.py"; then
    git -C "$source_dir" apply "$shaderc_tag_patch"
fi
if ! rg -q 'NDK_BUILD_TAG' \
    "$source_dir/third_party/spirv-tools/utils/update_build_version.py"; then
    git -C "$source_dir/third_party/spirv-tools" apply "$spirv_tools_tag_patch"
fi

cmake -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$install_dir" \
    -DCMAKE_EXE_LINKER_FLAGS='-static-libgcc -static-libstdc++' \
    -DSHADERC_ENABLE_WERROR_COMPILE=OFF \
    -DSHADERC_SKIP_COPYRIGHT_CHECK=ON \
    -DSHADERC_SKIP_EXAMPLES=ON \
    -DSHADERC_SKIP_TESTS=ON \
    -DSPIRV_SKIP_TESTS=ON \
    -DSPIRV_WERROR=OFF

NDK_BUILD_TAG=ndk-r26c cmake --build "$build_dir" --parallel "$jobs" --target \
    glslc_exe spirv-as spirv-cfg spirv-dis spirv-link spirv-opt spirv-reduce spirv-val

mkdir -p "$install_dir/bin"
for tool in glslc spirv-as spirv-cfg spirv-dis spirv-link spirv-opt spirv-reduce spirv-val; do
    tool_path=$(find "$build_dir" -type f -name "$tool" -perm -u+x -print -quit)
    if [[ -z "$tool_path" ]]; then
        echo "Built shader tool not found: $tool" >&2
        exit 1
    fi
    install -m 0755 "$tool_path" "$install_dir/bin/$tool"
done

file "$install_dir"/bin/*
