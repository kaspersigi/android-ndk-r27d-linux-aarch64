#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
source_dir="$project_root/sources/swig"
build_dir="$project_root/build/swig-linux-x86_64"
install_dir="$project_root/out/swig-linux-x86_64"

if [[ ! -x "$source_dir/configure" ]]; then
    echo "Missing SWIG source tree: $source_dir" >&2
    exit 1
fi

mkdir -p "$build_dir" "$install_dir"
(
    cd "$build_dir"
    CPPFLAGS="-I$build_dir${CPPFLAGS:+ $CPPFLAGS}" \
    "$source_dir/configure" \
        --prefix="$install_dir" \
        --without-pcre \
        --disable-ccache
)
# Android's pinned SWIG checkout has generated autotools files whose timestamps
# can trigger a bootstrap on a fresh clone. Keep that one-time regeneration and
# the Bison parser build serial; parallel make races config.status/parser.h.
# The explicit build-root include also preserves the include path present in
# SWIG's checked-in Makefile.in if the host automake regenerates it.
make -C "$build_dir" -j1
make -C "$build_dir" install
"$install_dir/bin/swig" -version
