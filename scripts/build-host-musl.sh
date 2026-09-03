#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$project_root/sources/musl"
build_dir="$project_root/build/musl-linux-aarch64"
install_dir="$project_root/out/musl-linux-aarch64"
jobs=${JOBS:-$(nproc)}

mkdir -p "$build_dir" "$install_dir"
(
    cd "$build_dir"
    CROSS_COMPILE=aarch64-linux-gnu- \
    CC=aarch64-linux-gnu-gcc \
    CFLAGS="-O2 -I$source_dir/android/include" \
    "$source_dir/configure" \
        --target=aarch64-linux-musl \
        --prefix="$install_dir" \
        --syslibdir="$install_dir/lib" \
        --disable-wrapper
)
make -C "$build_dir" -j"$jobs"
make -C "$build_dir" install
cp -L "$install_dir/lib/libc.so" "$install_dir/lib/libc_musl.so"
file "$install_dir/lib/libc_musl.so"
