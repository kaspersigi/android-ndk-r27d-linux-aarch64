#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$project_root/sources/swig"
build_dir="$project_root/build/swig-linux-x86_64"
install_dir="$project_root/out/swig-linux-x86_64"
jobs=${JOBS:-$(nproc)}

if [[ ! -x "$source_dir/configure" ]]; then
    echo "Missing SWIG source tree: $source_dir" >&2
    exit 1
fi

mkdir -p "$build_dir" "$install_dir"
(
    cd "$build_dir"
    "$source_dir/configure" \
        --prefix="$install_dir" \
        --without-pcre \
        --disable-ccache
)
make -C "$build_dir" -j"$jobs"
make -C "$build_dir" install
"$install_dir/bin/swig" -version
