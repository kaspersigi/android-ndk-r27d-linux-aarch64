#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$project_root/scripts/build-jobs.sh"
jobs=$(resolve_build_jobs)
native_protobuf_build="$project_root/build/protobuf-native"
cross_protobuf_build="$project_root/build/protobuf-linux-aarch64"
deps_install="$project_root/out/simpleperf-deps-linux-aarch64"
generated="$project_root/build/simpleperf-generated"
proto_staging="$project_root/build/simpleperf-proto-input"
build_dir="$project_root/build/simpleperf-report-linux-aarch64-gcc"
install_dir="$project_root/out/simpleperf-linux-aarch64"
toolchain="$project_root/cmake/linux-aarch64-toolchain.cmake"
gcc_toolchain="$project_root/cmake/linux-aarch64-gcc-toolchain.cmake"

mkdir -p "$native_protobuf_build" "$cross_protobuf_build" "$deps_install" \
    "$generated/system/extras/simpleperf" \
    "$proto_staging/system/extras/simpleperf" "$build_dir" "$install_dir"

if ! grep -q 'LIBBASE_ANDROID_30_AVAILABLE' \
    "$project_root/sources/system-libbase/logging.cpp"; then
  patch -d "$project_root/sources/system-libbase" -p1 \
      < "$project_root/patches/libbase-linux-aarch64-gcc.patch"
fi
if ! grep -q 'struct sigaction new_action = {};' \
    "$project_root/sources/system-unwinding/libunwindstack/ThreadUnwinder.cpp"; then
  patch -d "$project_root/sources/system-unwinding" -p1 \
      < "$project_root/patches/libunwindstack-linux-aarch64-gcc.patch"
fi
if ! grep -q '#include <cstdint>' \
    "$project_root/sources/system-extras/simpleperf/event_attr.h" || \
   ! grep -q '#include <functional>' \
    "$project_root/sources/system-extras/simpleperf/event_type.h" || \
   ! grep -q 'ifs_(std::string(file_path))' \
    "$project_root/sources/system-extras/simpleperf/utils.h" || \
   ! grep -q '#if defined(_LIBCPP_VERSION)' \
    "$project_root/sources/system-extras/simpleperf/read_elf.cpp" || \
   ! grep -q '#include <cstdint>' \
    "$project_root/sources/system-extras/simpleperf/read_elf.h"; then
  patch -d "$project_root/sources/system-extras" -p1 \
      < "$project_root/patches/simpleperf-linux-aarch64-gcc.patch"
fi

cmake -S "$project_root/sources/protobuf" -B "$native_protobuf_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-I$project_root/sources/protobuf/config" \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_WITH_ZLIB=OFF
cmake --build "$native_protobuf_build" --parallel "$jobs" --target protoc

cmake -S "$project_root/sources/protobuf" -B "$cross_protobuf_build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain" \
    -DCMAKE_INSTALL_PREFIX="$deps_install" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DCMAKE_CXX_FLAGS="-I$project_root/sources/protobuf/config" \
    -Dprotobuf_BUILD_TESTS=OFF \
    -Dprotobuf_BUILD_PROTOC_BINARIES=OFF \
    -Dprotobuf_BUILD_LIBPROTOC=OFF \
    -Dprotobuf_WITH_ZLIB=OFF
cmake --build "$cross_protobuf_build" --parallel "$jobs" --target libprotobuf-lite
mkdir -p "$deps_install/lib"
install -m 0644 "$cross_protobuf_build/libprotobuf-lite.a" \
    "$deps_install/lib/libprotobuf-lite.a"

install -m 0644 "$project_root/sources/system-extras/simpleperf/record_file.proto" \
    "$proto_staging/system/extras/simpleperf/record_file.proto"
"$native_protobuf_build/protoc" \
    -I "$proto_staging" \
    --cpp_out="lite:$generated" \
    "$proto_staging/system/extras/simpleperf/record_file.proto"
python3 "$project_root/sources/system-extras/simpleperf/event_table_generator.py" \
    "$project_root/sources/system-extras/simpleperf/event_table.json" \
    "$generated/event_table.cpp"

cmake -S "$project_root/cmake/simpleperf-linux-aarch64" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$gcc_toolchain" \
    -DNDK_PROJECT_ROOT="$project_root"
cmake --build "$build_dir" --parallel "$jobs" \
    --target simpleperf_report rust_demangle_smoke
install -m 0755 "$build_dir/libsimpleperf_report.so" \
    "$install_dir/libsimpleperf_report.so"
file "$install_dir/libsimpleperf_report.so"
