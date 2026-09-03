#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

checkout_commit() {
    local url=$1
    local destination=$2
    local commit=$3

    if [[ -d "$destination/.git" ]]; then
        local actual
        actual=$(git -C "$destination" rev-parse --verify HEAD 2>/dev/null || true)
        if [[ -z "$actual" ]]; then
            git -C "$destination" fetch --depth 1 origin "$commit"
            git -C "$destination" checkout --detach FETCH_HEAD
            return
        elif [[ "$actual" != "$commit" ]]; then
            echo "Unexpected revision in $destination: $actual (expected $commit)" >&2
            exit 1
        fi
        return
    fi

    mkdir -p "$destination"
    git -C "$destination" init
    git -C "$destination" remote add origin "$url"
    git -C "$destination" fetch --depth 1 origin "$commit"
    git -C "$destination" checkout --detach FETCH_HEAD
}

checkout_commit \
    https://android.googlesource.com/toolchain/llvm-project \
    "$project_root/sources/llvm-project" \
    d8003a456d14a3deb8054cdaa529ffbf02d9b262
checkout_commit \
    https://android.googlesource.com/toolchain/llvm_android \
    "$project_root/sources/llvm_android" \
    3503453cd6ccac933b4a1ec5255b7fc29851ea6b
checkout_commit \
    https://android.googlesource.com/platform/ndk \
    "$project_root/sources/ndk" \
    99de7583356a3ae1af2686e0659b646bdacb88c7
checkout_commit \
    https://android.googlesource.com/toolchain/make \
    "$project_root/sources/make" \
    06b4d6bea1e742a8e5ea2c4433abd381db054337
checkout_commit \
    https://android.googlesource.com/toolchain/yasm \
    "$project_root/sources/yasm" \
    7a28367b72cb1e1667b081d6404afbd063898e70
checkout_commit \
    https://android.googlesource.com/platform/external/shaderc/shaderc \
    "$project_root/sources/shaderc" \
    8045a61b8c6b79c9fdaa86f36653a824880bab4d
checkout_commit \
    https://android.googlesource.com/platform/external/shaderc/glslang \
    "$project_root/sources/shaderc/third_party/glslang" \
    2222fa5818324771ceb99fd8802e54a50a2fb1a4
checkout_commit \
    https://android.googlesource.com/platform/external/shaderc/spirv-tools \
    "$project_root/sources/shaderc/third_party/spirv-tools" \
    12f5c853ee9e06ba6565006d8d36ee261a140d91
checkout_commit \
    https://android.googlesource.com/platform/external/shaderc/spirv-headers \
    "$project_root/sources/shaderc/third_party/spirv-headers" \
    907059dfed550925a45217e1ed9a7bc42ff8d770
checkout_commit \
    https://android.googlesource.com/platform/external/python/cpython3 \
    "$project_root/sources/cpython3" \
    bb6b562da7dac38077ea6eecf7dbf4b763bb8202
checkout_commit \
    https://android.googlesource.com/platform/prebuilts/python/linux-x86 \
    "$project_root/sources/python-prebuilt-reference" \
    fce2346610379fdcce9dc7423c0e9a04e1a43cbf
checkout_commit \
    https://android.googlesource.com/platform/external/libedit \
    "$project_root/sources/libedit" \
    892b8b381ae82ac3184900d989a516854d8b1197
checkout_commit \
    https://android.googlesource.com/platform/external/libxml2 \
    "$project_root/sources/libxml2" \
    393a172b4d91f3677beb3d98568a94b08f014fcf
checkout_commit \
    https://android.googlesource.com/platform/external/ncurses \
    "$project_root/sources/ncurses" \
    34cc24447dc9e5700110580c784d9606f6cff5f0
checkout_commit \
    https://android.googlesource.com/platform/external/bzip2 \
    "$project_root/sources/bzip2" \
    449c870c546d8ce8c72d6c022361fc43eaa4adb4
checkout_commit \
    https://android.googlesource.com/platform/external/libffi \
    "$project_root/sources/libffi" \
    d8a9381107763f37b279ee1a0c656667cc11244a
checkout_commit \
    https://android.googlesource.com/platform/external/swig \
    "$project_root/sources/swig" \
    d0f0f90be16c2ac553b5fa08512045273135147a
checkout_commit \
    https://android.googlesource.com/platform/external/zlib \
    "$project_root/sources/zlib" \
    ad56eadd4af7749614d803c48c6aaba92461011f
checkout_commit \
    https://android.googlesource.com/platform/external/zstd \
    "$project_root/sources/zstd" \
    bf5d66e5db49af979e080d4a030a02f07cf84ccb
checkout_commit \
    https://github.com/besser82/libxcrypt.git \
    "$project_root/sources/libxcrypt" \
    99da23588acc5986159acca85b97cb7b208e739f
checkout_commit \
    https://github.com/bminor/glibc.git \
    "$project_root/sources/glibc-2.17" \
    c758a6861537815c759cba2018a3b1abb1943842
checkout_commit \
    https://android.googlesource.com/platform/prebuilts/simpleperf \
    "$project_root/sources/simpleperf-prebuilt" \
    ec4d791d52db4e98eba9544c1b865215d29b6634
checkout_commit \
    https://android.googlesource.com/platform/system/extras \
    "$project_root/sources/system-extras" \
    d4ef0af50486645fa372061ad2e61e4a493f0416
checkout_commit \
    https://android.googlesource.com/platform/bionic \
    "$project_root/sources/bionic" \
    14f00977391a24100467c3c7e4247cbfa5f3f98d
checkout_commit \
    https://android.googlesource.com/platform/system/libbase \
    "$project_root/sources/system-libbase" \
    5b5c21131b0ac22c610e8e06e266ff80b06aec9a
checkout_commit \
    https://android.googlesource.com/platform/system/libprocinfo \
    "$project_root/sources/system-libprocinfo" \
    f7dced08ba8d718ee8c6e64331942be468084efa
checkout_commit \
    https://android.googlesource.com/platform/system/libziparchive \
    "$project_root/sources/system-libziparchive" \
    0f74e0d2b5981eb3afd47e0d9f9406bdad6e5005
checkout_commit \
    https://android.googlesource.com/platform/system/logging \
    "$project_root/sources/system-logging" \
    a585c3ff993e0ecf692bff3a8c3045e22da5fd21
checkout_commit \
    https://android.googlesource.com/platform/system/unwinding \
    "$project_root/sources/system-unwinding" \
    26147ba63efcc44aedfb18dc715e806d0b08483c
checkout_commit \
    https://android.googlesource.com/platform/system/core \
    "$project_root/sources/system-core" \
    54a6fab636390eaa771d3f776058b38ecead2a96
checkout_commit \
    https://android.googlesource.com/platform/external/OpenCSD \
    "$project_root/sources/opencsd" \
    eeee0b1825146a6565edf1d1f913f74796f9f332
checkout_commit \
    https://android.googlesource.com/platform/external/libevent \
    "$project_root/sources/libevent" \
    0c609c857a6e55907f9e2485b0e9d1b7c878f794
checkout_commit \
    https://android.googlesource.com/platform/external/fmtlib \
    "$project_root/sources/fmtlib" \
    790cbdbe85f972eada1185fcc5d2d8bbca11d673
checkout_commit \
    https://android.googlesource.com/platform/external/lzma \
    "$project_root/sources/lzma" \
    96eb14d5ae3403195ecb2ba57353e8b1efbe85e2
checkout_commit \
    https://android.googlesource.com/platform/external/musl \
    "$project_root/sources/musl" \
    d5266f5433a1c21f6d80f63c628434550c6c1b76
checkout_commit \
    https://android.googlesource.com/platform/external/protobuf \
    "$project_root/sources/protobuf" \
    4140e0a3dcc49eb81fa7bade6110e04fe8496045
checkout_commit \
    https://android.googlesource.com/platform/external/rust/crates/rustc-demangle-capi \
    "$project_root/sources/rustc-demangle-capi" \
    d559e1fd988256e553f4fd6cc90abb59c658f702
