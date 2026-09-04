#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$project_root/scripts/build-jobs.sh"
jobs=$(resolve_build_jobs)
toolchain_file="$project_root/cmake/linux-aarch64-toolchain.cmake"
prefix="$project_root/out/host-deps-linux-aarch64"
build_root="$project_root/build/host-deps-linux-aarch64"

for command in aarch64-linux-gnu-gcc aarch64-linux-gnu-ar cmake make; do
    command -v "$command" >/dev/null || {
        echo "Missing required command: $command" >&2
        exit 1
    }
done

mkdir -p "$prefix/include" "$prefix/lib" "$build_root"

# bzip2: build a PIC static library so CPython's extension has no additional
# runtime dependency outside the package.
bzip_build="$build_root/bzip2"
mkdir -p "$bzip_build"
bzip_objects=()
for source in blocksort huffman crctable randtable compress decompress bzlib; do
    object="$bzip_build/$source.o"
    aarch64-linux-gnu-gcc -O2 -fPIC -I"$project_root/sources/bzip2" \
        -c "$project_root/sources/bzip2/$source.c" -o "$object"
    bzip_objects+=("$object")
done
aarch64-linux-gnu-ar rcs "$prefix/lib/libbz2.a" "${bzip_objects[@]}"
install -m 0644 "$project_root/sources/bzip2/bzlib.h" "$prefix/include/bzlib.h"

# AOSP's libffi CMake file is Windows-only. Reproduce its Android.bp source
# selection for AArch64 and create a PIC static library for CPython _ctypes.
libffi_build="$build_root/libffi"
mkdir -p "$libffi_build"
"$project_root/sources/libffi/gen_ffi_header.sh" \
    < "$project_root/sources/libffi/include/ffi.h.in" \
    > "$prefix/include/ffi.h"
install -m 0644 "$project_root/sources/libffi/src/aarch64/ffitarget.h" \
    "$prefix/include/ffitarget.h"
install -m 0644 "$project_root/sources/libffi/linux-arm64/fficonfig.h" \
    "$prefix/include/fficonfig.h"
libffi_objects=()
for source in \
    src/closures.c src/debug.c src/java_raw_api.c src/prep_cif.c \
    src/raw_api.c src/types.c src/aarch64/ffi.c src/aarch64/sysv.S; do
    object="$libffi_build/${source//\//_}.o"
    aarch64-linux-gnu-gcc -O2 -fPIC \
        -I"$prefix/include" \
        -I"$project_root/sources/libffi/include" \
        -I"$project_root/sources/libffi/src" \
        -I"$project_root/sources/libffi/src/aarch64" \
        -c "$project_root/sources/libffi/$source" -o "$object"
    libffi_objects+=("$object")
done
aarch64-linux-gnu-ar rcs "$prefix/lib/libffi.a" "${libffi_objects[@]}"

# CPython's r27d file inventory contains the optional _crypt extension. The
# official x86_64 Python prebuilt links to libcrypt.so.1, so provide the same
# ABI from the canonical libxcrypt implementation for AArch64.
libxcrypt_build="$build_root/libxcrypt"
mkdir -p "$libxcrypt_build"
autoreconf -fi "$project_root/sources/libxcrypt"
(
    cd "$libxcrypt_build"
    CC=aarch64-linux-gnu-gcc \
    AR=aarch64-linux-gnu-ar \
    RANLIB=aarch64-linux-gnu-ranlib \
    CFLAGS='-O2 -fPIC' \
    "$project_root/sources/libxcrypt/configure" \
        --build=x86_64-linux-gnu \
        --host=aarch64-linux-gnu \
        --prefix="$prefix" \
        --enable-shared \
        --enable-static \
        --disable-werror
)
make -C "$libxcrypt_build" -j"$jobs"
make -C "$libxcrypt_build" install

# zlib is needed by CPython, LLDB and Simpleperf. Keep both shared and static
# variants; packaged host tools may use the shared SONAME available on Linux.
cmake -S "$project_root/sources/zlib" -B "$build_root/zlib" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DCMAKE_POSITION_INDEPENDENT_CODE=ON \
    -DZLIB_BUILD_EXAMPLES=OFF
cmake --build "$build_root/zlib" --parallel "$jobs"
cmake --install "$build_root/zlib"

build_ncurses() {
    local suffix=$1
    local build_dir="$build_root/ncurses${suffix}"
    local wide_options=()
    if [[ "$suffix" == "w" ]]; then
        wide_options+=(--enable-widec)
    fi
    mkdir -p "$build_dir"
    (
        cd "$build_dir"
        # GCC 15 defaults to C23, where bool is a keyword. Ncurses 6.3 then
        # generates a C++-hostile `#define bool`; use the C dialect from the
        # original release era so curses.h preserves native C++ bool.
        CC=aarch64-linux-gnu-gcc \
        CXX=aarch64-linux-gnu-g++ \
        AR=aarch64-linux-gnu-ar \
        RANLIB=aarch64-linux-gnu-ranlib \
        CFLAGS='-O2 -fPIC -std=gnu17' \
        "$project_root/sources/ncurses/configure" \
            --build=x86_64-linux-gnu \
            --host=aarch64-linux-gnu \
            --prefix="$prefix" \
            --with-shared \
            --with-normal \
            --without-ada \
            --without-cxx-binding \
            --without-debug \
            --without-manpages \
            --without-progs \
            --without-tests \
            "${wide_options[@]}"
    )
    make -C "$build_dir" -j"$jobs"
    make -C "$build_dir" install.libs install.includes
}
build_ncurses ""
build_ncurses w

# Build the exact libedit and libxml2 revisions recorded in Google's r27d
# Clang BUILD_INFO.
libedit_build="$build_root/libedit"
mkdir -p "$libedit_build"
autoreconf -fi "$project_root/sources/libedit"
(
    cd "$libedit_build"
    CC=aarch64-linux-gnu-gcc \
    AR=aarch64-linux-gnu-ar \
    RANLIB=aarch64-linux-gnu-ranlib \
    CPPFLAGS="-I$prefix/include" \
    LDFLAGS="-L$prefix/lib -Wl,-rpath-link,$prefix/lib" \
    LIBS='-lncurses' \
    "$project_root/sources/libedit/configure" \
        --build=x86_64-linux-gnu \
        --host=aarch64-linux-gnu \
        --prefix="$prefix" \
        --disable-maintainer-mode \
        --enable-shared \
        --disable-static
)
make -C "$libedit_build/src" -j"$jobs"
make -C "$libedit_build/src" install

cmake -S "$project_root/sources/libxml2" -B "$build_root/libxml2" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
    -DCMAKE_INSTALL_PREFIX="$prefix" \
    -DBUILD_SHARED_LIBS=ON \
    -DLIBXML2_WITH_ICONV=OFF \
    -DLIBXML2_WITH_LZMA=OFF \
    -DLIBXML2_WITH_PYTHON=OFF \
    -DLIBXML2_WITH_TESTS=OFF \
    -DLIBXML2_WITH_ZLIB=OFF
cmake --build "$build_root/libxml2" --parallel "$jobs"
cmake --install "$build_root/libxml2"

file "$prefix"/lib/libedit.so* "$prefix"/lib/libxml2.so* \
    "$prefix"/lib/libncurses.so* "$prefix"/lib/libncursesw.so*
