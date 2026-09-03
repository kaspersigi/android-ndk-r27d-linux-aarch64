#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
jobs=${JOBS:-$(nproc)}
source_date_epoch=${SOURCE_DATE_EPOCH:-1751932800}
make_source="$project_root/sources/make"
yasm_source="$project_root/sources/yasm"
make_build="$project_root/build/make-linux-aarch64"
yasm_build="$project_root/build/yasm-linux-aarch64"
install_dir="$project_root/out/host-tools-linux-aarch64"

for command in aarch64-linux-gnu-gcc aarch64-linux-gnu-ar make; do
    if ! command -v "$command" >/dev/null; then
        echo "Missing required command: $command" >&2
        exit 1
    fi
done

if [[ ! -x "$make_source/configure" ]]; then
    echo "Missing GNU Make source tree: $make_source" >&2
    exit 1
fi
if [[ ! -x "$yasm_source/configure" ]]; then
    echo "Missing Yasm source tree: $yasm_source" >&2
    exit 1
fi

mkdir -p "$make_build" "$yasm_build" "$install_dir"

(
    cd "$make_build"
    CC=aarch64-linux-gnu-gcc \
    AR=aarch64-linux-gnu-ar \
    RANLIB=aarch64-linux-gnu-ranlib \
    CFLAGS='-O2' \
    LDFLAGS='-static-libgcc' \
    "$make_source/configure" \
        --host=aarch64-linux-gnu \
        --prefix="$install_dir" \
        --disable-maintainer-mode \
        --disable-nls \
        --without-guile
)
# Android's checked-in Soong config for this exact source revision identifies
# the release as 4.3; autotools regenerates a development-only 4.3.90 label.
sed -i \
    -e 's/^#define PACKAGE_VERSION "4\.3\.90"/#define PACKAGE_VERSION "4.3"/' \
    -e 's/^#define VERSION "4\.3\.90"/#define VERSION "4.3"/' \
    "$make_build/src/config.h"
SOURCE_DATE_EPOCH="$source_date_epoch" \
    make -C "$make_build" -j"$jobs" MAKE_MAINTAINER_MODE= MAKE_CFLAGS=
make -C "$make_build" install

(
    cd "$yasm_build"
    CC=aarch64-linux-gnu-gcc \
    AR=aarch64-linux-gnu-ar \
    RANLIB=aarch64-linux-gnu-ranlib \
    CFLAGS='-O2 -std=gnu17' \
    LDFLAGS='-static-libgcc' \
    "$yasm_source/configure" \
        --host=aarch64-linux-gnu \
        --prefix="$install_dir"
)
SOURCE_DATE_EPOCH="$source_date_epoch" make -C "$yasm_build" -j"$jobs"
make -C "$yasm_build" install

file "$install_dir/bin/make" "$install_dir/bin/yasm"
