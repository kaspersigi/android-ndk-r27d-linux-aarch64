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
host_runtime_dir="$toolchain/lib/aarch64-unknown-linux-gnu"
compiler_rt_dir="$toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu"
qemu_prefix=${QEMU_LD_PREFIX:-/usr/aarch64-linux-gnu}
validation_root=$(mktemp -d "$project_root/build/validation.XXXXXX")

if [[ ! -x "$toolchain/bin/clang" ]]; then
    echo "Invalid package root: $package_root" >&2
    exit 1
fi

python3 -B "$project_root/tests/compare_reference_layout_test.py"
"$project_root/tests/check-aarch64-elf-test.sh"
"$project_root/tests/check-aarch64-host-archives-test.sh"

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

read_elf_dynamic_section() {
    local path=$1 output

    if ! output=$(readelf -d -- "$path" 2>&1); then
        echo "Failed to read ELF dynamic section: $path" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    if grep -Fq 'Error:' <<< "$output"; then
        echo "Invalid ELF dynamic section: $path" >&2
        printf '%s\n' "$output" >&2
        return 1
    fi
    printf '%s\n' "$output"
}

check_needed_libraries() {
    local path=$1
    local allow_libgcc=$2
    local dependency dynamic_section

    "$project_root/scripts/check-aarch64-elf.sh" "$path"
    dynamic_section=$(read_elf_dynamic_section "$path") || exit 1

    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-aarch64.so.1)
                ;;
            libgcc_s.so.1)
                if [[ "$allow_libgcc" != "1" ]]; then
                    echo "Unexpected external shared-library dependency in $path: $dependency" >&2
                    exit 1
                fi
                ;;
            *)
                echo "Unexpected external shared-library dependency in $path: $dependency" >&2
                exit 1
                ;;
        esac
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        <<< "$dynamic_section")
}

declare -A packaged_host_sonames=()
host_elf_count=0

validate_ndk_host_elf() {
    local path=$1
    case "$path" in
        "$compiler_rt_dir/clang_rt.crtbegin.o"|\
        "$compiler_rt_dir/clang_rt.crtend.o")
            "$project_root/scripts/check-aarch64-elf.sh" \
                --allow-relocatable "$path"
            ;;
        *)
            "$project_root/scripts/check-aarch64-elf.sh" "$path"
            ;;
    esac
}

register_packaged_host_sonames() {
    local root=$1
    local scope=$2
    local path kind soname dynamic_section
    local -a find_args=("$root")

    [[ -d "$root" ]] || {
        echo "Missing NDK host directory: $root" >&2
        exit 1
    }
    if [[ "$scope" == "shallow" ]]; then
        find_args+=(-maxdepth 1)
    fi

    while IFS= read -r -d '' path; do
        kind=$(file -b -- "$path")
        [[ "$kind" == ELF* ]] || continue
        validate_ndk_host_elf "$path"
        dynamic_section=$(read_elf_dynamic_section "$path") || exit 1
        soname=$(sed -n 's/.*Library soname: \[\([^]]*\)\].*/\1/p' \
            <<< "$dynamic_section")
        if [[ -n "$soname" ]]; then
            packaged_host_sonames["$soname"]=$path
        fi
    done < <(find "${find_args[@]}" -type f -print0)
}

check_host_dependency_closure() {
    local path=$1
    local dependency dynamic_section
    local nis_extension="$toolchain/python3/lib/python3.11/lib-dynload/nis.cpython-311-aarch64-linux-gnu.so"

    dynamic_section=$(read_elf_dynamic_section "$path") || exit 1

    while IFS= read -r dependency; do
        case "$dependency" in
            libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|ld-linux-aarch64.so.1)
                ;;
            libnsl.so.1)
                [[ "$path" == "$nis_extension" ]] || {
                    echo "Unexpected external shared-library dependency in $path: $dependency" >&2
                    exit 1
                }
                ;;
            libgcc_s.so.1)
                [[ "$path" == "$compiler_rt_dir/"* ]] || {
                    echo "Unexpected external shared-library dependency in $path: $dependency" >&2
                    exit 1
                }
                ;;
            *)
                [[ ${packaged_host_sonames[$dependency]+present} ]] || {
                    echo "NDK host ELF depends on an unpackaged shared library in $path: $dependency" >&2
                    exit 1
                }
                ;;
        esac
    done < <(sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
        <<< "$dynamic_section")
}

scan_ndk_host_elfs() {
    local root=$1
    local scope=$2
    local path kind
    local -a find_args=("$root")

    if [[ "$scope" == "shallow" ]]; then
        find_args+=(-maxdepth 1)
    fi

    while IFS= read -r -d '' path; do
        kind=$(file -b -- "$path")
        [[ "$kind" == ELF* ]] || continue
        check_host_dependency_closure "$path"
        ((host_elf_count += 1))
    done < <(find "${find_args[@]}" -type f -print0)
}

host_run "$toolchain/bin/clang" --version
host_run "$toolchain/bin/llvm-config" --targets-built
host_run "$toolchain/bin/ld.lld" --version
if [[ -x "$toolchain/bin/llvm-bolt" ]]; then
    host_run "$toolchain/bin/llvm-bolt" --version
fi
host_run "$toolchain/bin/lldb" --version
host_run "$toolchain/python3/bin/python3.11" -c \
    'import _ctypes, bz2, curses, nis, zlib; print("python-host-ok")'

for name in libc++.so libc++abi.so libunwind.so; do
    runtime="$host_runtime_dir/$name"
    dynamic_section=
    [[ -f "$runtime" ]] || {
        echo "Required host runtime is missing: $runtime" >&2
        exit 1
    }
    dynamic_section=$(read_elf_dynamic_section "$runtime") || exit 1
    grep -Fq "Library soname: [$name]" <<< "$dynamic_section" || {
        echo "Unexpected host-runtime SONAME: $runtime" >&2
        exit 1
    }
    check_needed_libraries "$runtime" 0
    host_run "$toolchain/python3/bin/python3.11" -c \
        'import ctypes, sys; ctypes.CDLL(sys.argv[1])' "$runtime"
done

compiler_rt_shared_count=0
while IFS= read -r -d '' runtime; do
    check_needed_libraries "$runtime" 1
    ((compiler_rt_shared_count += 1))
done < <(find "$compiler_rt_dir" -maxdepth 1 -type f -name '*.so' -print0)
if (( compiler_rt_shared_count == 0 )); then
    echo "No compiler-rt shared libraries found in $compiler_rt_dir" >&2
    exit 1
fi
echo "compiler_rt_shared_libraries=$compiler_rt_shared_count"

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

recursive_host_roots=(
    "$toolchain/bin"
    "$toolchain/python3"
    "$toolchain/lib/python3.11"
    "$host_prebuilt/bin"
    "$shader_tools"
    "$simpleperf_tools"
)
shallow_host_roots=(
    "$toolchain/lib"
    "$host_runtime_dir"
    "$compiler_rt_dir"
    "$toolchain/musl/lib"
)

for root in "${recursive_host_roots[@]}"; do
    register_packaged_host_sonames "$root" recursive
done
for root in "${shallow_host_roots[@]}"; do
    register_packaged_host_sonames "$root" shallow
done
for root in "${recursive_host_roots[@]}"; do
    scan_ndk_host_elfs "$root" recursive
done
for root in "${shallow_host_roots[@]}"; do
    scan_ndk_host_elfs "$root" shallow
done
echo "packaged_host_sonames=${#packaged_host_sonames[@]}"
echo "ndk_host_elf_files=$host_elf_count"

"$project_root/scripts/check-aarch64-host-archives.sh" "$package_root"
"$project_root/scripts/compare-reference-layout.py" "$package_root" \
    --reference "${REFERENCE_NDK:-/mnt/develop/android-ndk-r27d}"

echo "Validation output: $validation_root"
