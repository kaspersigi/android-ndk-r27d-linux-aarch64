#!/usr/bin/env bash
set -euo pipefail
export PYTHONDONTWRITEBYTECODE=1

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_root=${1:-$project_root/dist/android-ndk-r27d}
if [[ ! -d "$package_root" ]]; then
    echo "Invalid package root: $package_root" >&2
    exit 1
fi
package_root=$(realpath -e -- "$package_root")
toolchain="$package_root/toolchains/llvm/prebuilt/linux-aarch64"
host_prebuilt="$package_root/prebuilt/linux-aarch64"
shader_tools="$package_root/shader-tools/linux-aarch64"
simpleperf_tools="$package_root/simpleperf/bin/linux/aarch64"
qemu_prefix=${QEMU_LD_PREFIX:-/usr/aarch64-linux-gnu}
validation_root=$(mktemp -d "$project_root/build/validation.XXXXXX")

if [[ ! -x "$toolchain/bin/clang" ]]; then
    echo "Invalid package root: $package_root" >&2
    exit 1
fi

python3 -B "$project_root/tests/compare_reference_layout_test.py"

"$project_root/scripts/compare-reference-layout.py" "$package_root" \
    --reference "${REFERENCE_NDK:-/mnt/develop/android-ndk-r27d}"

while IFS= read -r -d '' extension; do
    readelf -d "$extension" | grep -Fq 'Library rpath: [$ORIGIN/../lib]' || {
        echo "Invalid Python extension RPATH: $extension" >&2
        exit 1
    }
done < <(find "$toolchain/python3/lib/python3.11/lib-dynload" \
    -type f -name '*.so' -print0)

case $(uname -m) in
    aarch64|arm64)
        host_run() { "$@"; }
        ndk_build_run() { "$package_root/ndk-build" "$@"; }
        cmake_launcher_options=()
        ;;
    *)
        command -v qemu-aarch64 >/dev/null
        command -v aarch64-linux-gnu-gcc >/dev/null
        aarch64-linux-gnu-gcc "$project_root/tests/qemu_exec_probe.c" \
            -o "$validation_root/qemu-exec-probe"
        if ! QEMU_LD_PREFIX="$qemu_prefix" qemu-aarch64 \
            "$validation_root/qemu-exec-probe" \
            "$validation_root/qemu-exec-probe" --child; then
            echo "error: AArch64 child-process execution is unavailable" >&2
            echo "       install qemu-user-binfmt with ./scripts/resolute-install-deps.sh" >&2
            exit 1
        fi
        host_run() { QEMU_LD_PREFIX="$qemu_prefix" qemu-aarch64 "$@"; }
        ndk_build_run() {
            QEMU_LD_PREFIX="$qemu_prefix" qemu-aarch64 \
                "$validation_root/qemu-exec-probe" /bin/sh \
                "$package_root/ndk-build" "$@"
        }
        cmake_launcher_options=(
            -DCMAKE_C_COMPILER_LAUNCHER=qemu-aarch64
            -DCMAKE_CXX_COMPILER_LAUNCHER=qemu-aarch64
        )
        ;;
esac

host_run "$toolchain/bin/clang" --version
host_run "$toolchain/bin/llvm-config" --targets-built
host_run "$toolchain/bin/ld.lld" --version
if [[ -x "$toolchain/bin/llvm-bolt" ]]; then
    host_run "$toolchain/bin/llvm-bolt" --version
fi
host_run "$toolchain/bin/lldb" --version
host_run "$toolchain/python3/bin/python3.11" -c \
    'import _ctypes, bz2, curses, nis, zlib; print("python-host-ok")'
PYTHONPATH="$toolchain/lib/python3.11/site-packages" \
    host_run "$toolchain/python3/bin/python3.11" -c \
    'import lldb; print("lldb-python-ok", lldb.SBDebugger.GetVersionString())'
host_run "$host_prebuilt/bin/make" --version
host_run "$host_prebuilt/bin/yasm" --version
host_run "$shader_tools/glslc" --version
host_run "$shader_tools/glslc" -c "$project_root/tests/simple.vert" \
    -o "$validation_root/simple.vert.spv"
host_run "$shader_tools/spirv-val" "$validation_root/simple.vert.spv"
host_run "$simpleperf_tools/simpleperf" --version
host_run "$toolchain/python3/bin/python3.11" \
    "$project_root/tests/simpleperf_report_smoke.py" \
    "$simpleperf_tools/libsimpleperf_report.so" \
    "$project_root/sources/simpleperf-prebuilt/test/testdata/perf.data"
host_run "$project_root/build/simpleperf-report-linux-aarch64-gcc/rust_demangle_smoke"

targets=(
    armv7a-linux-androideabi21
    aarch64-linux-android21
    i686-linux-android21
    x86_64-linux-android21
    riscv64-linux-android35
)
for target in "${targets[@]}"; do
    host_run "$toolchain/bin/clang" \
        --target="$target" \
        --sysroot="$toolchain/sysroot" \
        -fuse-ld=lld \
        "$project_root/tests/android_hello.c" \
        -o "$validation_root/hello-$target"
    host_run "$toolchain/bin/clang++" \
        --target="$target" \
        --sysroot="$toolchain/sysroot" \
        -fuse-ld=lld \
        -fPIC -shared -stdlib=libc++ -static-libstdc++ \
        "$project_root/tests/android_hello.cpp" \
        -o "$validation_root/libhello-$target.so"
    file "$validation_root/hello-$target" "$validation_root/libhello-$target.so"
done

QEMU_LD_PREFIX="$qemu_prefix" cmake \
    -S "$project_root/tests/cmake-smoke" \
    -B "$validation_root/cmake-arm64-v8a" \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$package_root/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI=arm64-v8a \
    -DANDROID_PLATFORM=android-21 \
    -DANDROID_HOST_TAG=linux-aarch64 \
    "${cmake_launcher_options[@]}"
QEMU_LD_PREFIX="$qemu_prefix" cmake --build "$validation_root/cmake-arm64-v8a"
file "$validation_root/cmake-arm64-v8a/libndk_arm64_cmake_smoke.so"

(
    cd "$project_root/tests/ndk-build-smoke"
    ndk_build_run \
        HOST_ARCH=aarch64 \
        NDK_PROJECT_PATH=. \
        NDK_APPLICATION_MK=jni/Application.mk \
        NDK_OUT="$validation_root/ndk-build-obj" \
        NDK_LIBS_OUT="$validation_root/ndk-build-libs"
)
find "$validation_root/ndk-build-libs" -type f -name '*.so' -print0 \
    | sort -z | xargs -0 file

unexpected_host_elf="$validation_root/unexpected-host-elf.txt"
find "$toolchain/bin" \
    "$toolchain/python3" \
    "$toolchain/lib/python3.11" \
    "$host_prebuilt/bin" \
    "$shader_tools" \
    "$simpleperf_tools" \
    -type f -print0 \
    | xargs -0 file \
    | rg 'ELF ' \
    | rg -v 'ARM aarch64' > "$unexpected_host_elf" || true
find "$toolchain/lib" -maxdepth 1 -type f -print0 \
    | xargs -0 file \
    | rg 'ELF ' \
    | rg -v 'ARM aarch64' >> "$unexpected_host_elf" || true
find "$toolchain/lib/aarch64-unknown-linux-gnu" \
    "$toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu" \
    "$toolchain/musl/lib" -maxdepth 1 -type f -print0 \
    | xargs -0 file \
    | rg 'ELF ' \
    | rg -v 'ARM aarch64' >> "$unexpected_host_elf" || true
if [[ -s "$unexpected_host_elf" ]]; then
    echo "Non-AArch64 host ELF files found:" >&2
    cat "$unexpected_host_elf" >&2
    exit 1
fi

"$project_root/scripts/check-aarch64-host-archives.sh" "$package_root"
"$project_root/scripts/compare-reference-layout.py" "$package_root" \
    --reference "${REFERENCE_NDK:-/mnt/develop/android-ndk-r27d}"

echo "Validation output: $validation_root"
