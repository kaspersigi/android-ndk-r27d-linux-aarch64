#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$project_root/sources/cpython3"
build_dir="$project_root/build/python-linux-aarch64"
install_dir="$project_root/out/python-linux-aarch64"
deps="$project_root/out/host-deps-linux-aarch64"
build_python="$project_root/sources/python-prebuilt-reference/bin/python3.11"
jobs=${JOBS:-$(nproc)}
static_curses_patch="$project_root/patches/cpython-static-curses-deps.patch"

for required in \
    "$source_dir/configure" \
    "$build_python" \
    "$deps/include/zlib.h" \
    "$deps/include/bzlib.h" \
    "$deps/include/ffi.h" \
    "$deps/lib/libz.a" \
    "$deps/lib/libbz2.a" \
    "$deps/lib/libffi.a"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing Python build input: $required" >&2
        exit 1
    fi
done

if ! rg -q 'PYTHON_NDK_STATIC_DEPS' "$source_dir/setup.py"; then
    git -C "$source_dir" apply "$static_curses_patch"
fi

mkdir -p "$build_dir" "$install_dir"
host_runner="env QEMU_LD_PREFIX=/usr/aarch64-linux-gnu LD_LIBRARY_PATH=$deps/lib qemu-aarch64"

(
    cd "$build_dir"
    CC=aarch64-linux-gnu-gcc \
    CXX=aarch64-linux-gnu-g++ \
    AR=aarch64-linux-gnu-ar \
    RANLIB=aarch64-linux-gnu-ranlib \
    READELF=aarch64-linux-gnu-readelf \
    HOSTRUNNER="$host_runner" \
    CPPFLAGS="-I$deps/include -I$deps/include/ncursesw" \
    LDFLAGS="-L$deps/lib -Wl,-rpath-link,$deps/lib -Wl,-rpath,'\$\$ORIGIN/../lib'" \
    PKG_CONFIG_LIBDIR="$deps/lib/pkgconfig" \
    LIBCRYPT_CFLAGS="-I$deps/include" \
    LIBCRYPT_LIBS="$deps/lib/libcrypt.a" \
    ZLIB_CFLAGS="-I$deps/include" \
    ZLIB_LIBS="$deps/lib/libz.a" \
    BZIP2_CFLAGS="-I$deps/include" \
    BZIP2_LIBS="$deps/lib/libbz2.a" \
    ac_cv_file__dev_ptmx=yes \
    ac_cv_file__dev_ptc=no \
    ac_cv_buggy_getaddrinfo=no \
    "$source_dir/configure" \
        --build=x86_64-linux-gnu \
        --host=aarch64-linux-gnu \
        --prefix="$install_dir" \
        --enable-shared \
        --with-build-python="$build_python" \
        --with-ensurepip=no
)

# Configure can change an optional module's link inputs without invalidating an
# existing extension in an incremental build. Force _crypt to pick up the
# pinned static libxcrypt rather than retaining an older host SONAME.
find "$build_dir/build" -type f \( \
    -name '_crypt*.so' -o -name '_curses*.so' -o -name '_bz2*.so' -o \
    -name 'zlib*.so' -o -name 'binascii*.so' \
    \) -delete 2>/dev/null || true

PYTHON_NDK_STATIC_DEPS="$deps/lib" \
HOSTRUNNER="$host_runner" \
LD_LIBRARY_PATH="$deps/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    make -C "$build_dir" -j"$jobs"
PYTHON_NDK_STATIC_DEPS="$deps/lib" \
HOSTRUNNER="$host_runner" \
LD_LIBRARY_PATH="$deps/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
    make -C "$build_dir" install

file "$install_dir/bin/python3.11" "$install_dir/lib/libpython3.11.so.1.0"
LD_LIBRARY_PATH="$deps/lib" qemu-aarch64 -L /usr/aarch64-linux-gnu \
    "$install_dir/bin/python3.11" -VV

# Modern cross-development packages omit the legacy SunRPC/NIS headers even
# though glibc and libnsl retain the ABI used by Google's r27d Python prebuilt.
# Build the deprecated optional module with the matching glibc 2.17 headers.
nis_output="$install_dir/lib/python3.11/lib-dynload/nis.cpython-311-aarch64-linux-gnu.so"
aarch64-linux-gnu-gcc -O2 -fPIC -shared \
    -I"$install_dir/include/python3.11" \
    -I"$project_root/sources/glibc-2.17/sunrpc" \
    -I"$project_root/sources/glibc-2.17/nis" \
    "$source_dir/Modules/nismodule.c" \
    -Wl,--no-as-needed /usr/aarch64-linux-gnu/lib/libnsl.so.1 \
    -o "$nis_output"
file "$nis_output"
