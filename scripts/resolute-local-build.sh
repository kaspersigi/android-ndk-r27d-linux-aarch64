#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_name=android-ndk-r27d
archive_name=android-ndk-r27d-linux.zip
reference_revision=27.3.13750724
reference_url_default=https://dl.google.com/android/repository/android-ndk-r27d-linux.zip
reference_sha256_default=601246087a682d1944e1e16dd85bc6e49560fe8b6d61255be2829178c8ed15d9

usage() {
    cat <<'EOF'
Build, assemble, validate, and package Android NDK r27d for Linux AArch64.

Usage:
  ./scripts/resolute-local-build.sh

Environment:
  ALLOW_UNSUPPORTED_HOST=0  Require Ubuntu 26.04 (Resolute); set to 1 to bypass.
  CLEAN=0                   Set to 1 to remove sources/, build/, out/, and dist/
                            before building.
  JOBS=<n>                  Parallel build jobs; defaults to nproc.
  REFERENCE_NDK=<path>      Official Linux x86_64 android-ndk-r27d directory.
  REFERENCE_NDK_CACHE_DIR   Download/cache parent; defaults to .deps/.
  REFERENCE_NDK_URL         Official reference archive URL override.
  REFERENCE_NDK_SHA256      Expected reference archive SHA-256 override.

If REFERENCE_NDK is unset, an existing /mnt/develop/android-ndk-r27d is used.
Otherwise the official archive is downloaded, checksum-verified, and extracted
under REFERENCE_NDK_CACHE_DIR.

Outputs:
  dist/android-ndk-r27d/
  dist/android-ndk-r27d-linux.zip
  dist/android-ndk-r27d-linux.zip.sha256
EOF
}

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
fi

if (( $# != 0 )); then
    usage >&2
    exit 2
fi

require_boolean() {
    local name=$1
    local value=$2
    if [[ "$value" != "0" && "$value" != "1" ]]; then
        echo "error: $name must be 0 or 1" >&2
        exit 2
    fi
}

allow_unsupported_host=${ALLOW_UNSUPPORTED_HOST:-0}
clean=${CLEAN:-0}
jobs=${JOBS:-$(nproc)}
require_boolean ALLOW_UNSUPPORTED_HOST "$allow_unsupported_host"
require_boolean CLEAN "$clean"
if [[ ! "$jobs" =~ ^[1-9][0-9]*$ ]]; then
    echo "error: JOBS must be a positive integer" >&2
    exit 2
fi

if [[ ! -r /etc/os-release ]]; then
    echo "error: cannot identify the host because /etc/os-release is unavailable" >&2
    exit 1
fi

# /etc/os-release is the system-provided source of distribution metadata.
# shellcheck disable=SC1091
source /etc/os-release

ubuntu_codename=${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}
if [[ "$allow_unsupported_host" != "1" ]] && \
   { [[ "${ID:-}" != "ubuntu" ]] || \
     [[ "${VERSION_ID:-}" != "26.04" ]] || \
     [[ "$ubuntu_codename" != "resolute" ]]; }; then
    echo "error: this script supports Ubuntu 26.04 (Resolute); detected ${PRETTY_NAME:-unknown}" >&2
    echo "       set ALLOW_UNSUPPORTED_HOST=1 to continue at your own risk" >&2
    exit 1
fi

case $(uname -m) in
    x86_64|amd64)
        ;;
    *)
        echo "error: the two-stage cross build requires an x86_64 build host" >&2
        exit 1
        ;;
esac

required_commands=(
    aarch64-linux-gnu-ar
    aarch64-linux-gnu-g++
    aarch64-linux-gnu-gcc
    aarch64-linux-gnu-nm
    aarch64-linux-gnu-objcopy
    aarch64-linux-gnu-objdump
    aarch64-linux-gnu-ranlib
    aarch64-linux-gnu-readelf
    aarch64-linux-gnu-strip
    autoreconf
    awk
    cc
    c++
    clang
    clang++
    cmake
    curl
    file
    git
    make
    ninja
    patch
    perl
    pkg-config
    python3
    qemu-aarch64
    readelf
    rg
    rsync
    sha256sum
    unzip
    zip
)

missing_commands=()
for command_name in "${required_commands[@]}"; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
        missing_commands+=("$command_name")
    fi
done
if (( ${#missing_commands[@]} != 0 )); then
    printf 'error: missing required commands:' >&2
    printf ' %s' "${missing_commands[@]}" >&2
    printf '\n       run ./scripts/resolute-install-deps.sh first\n' >&2
    exit 1
fi

if [[ "$clean" == "1" ]]; then
    echo "Removing generated sources, build trees, outputs, and packages..."
    rm -rf -- \
        "$project_root/sources" \
        "$project_root/build" \
        "$project_root/out" \
        "$project_root/dist"
fi

reference_is_valid() {
    local candidate=$1
    local actual_revision
    [[ -f "$candidate/source.properties" ]] || return 1
    [[ -d "$candidate/toolchains/llvm/prebuilt/linux-x86_64" ]] || return 1
    actual_revision=$(awk -F= \
        '$1 ~ /^[[:space:]]*Pkg\.Revision[[:space:]]*$/ {
            value=$2
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
            print value
        }' "$candidate/source.properties")
    [[ "$actual_revision" == "$reference_revision" ]]
}

reference_cache_dir=${REFERENCE_NDK_CACHE_DIR:-$project_root/.deps}
reference_url=${REFERENCE_NDK_URL:-$reference_url_default}
reference_sha256=${REFERENCE_NDK_SHA256:-$reference_sha256_default}

if [[ -n "${REFERENCE_NDK:-}" ]]; then
    reference_ndk=$REFERENCE_NDK
elif reference_is_valid /mnt/develop/android-ndk-r27d; then
    reference_ndk=/mnt/develop/android-ndk-r27d
else
    reference_ndk="$reference_cache_dir/$package_name"
fi

if ! reference_is_valid "$reference_ndk"; then
    if [[ -n "${REFERENCE_NDK:-}" ]]; then
        echo "error: REFERENCE_NDK is not the official r27d Linux package: $reference_ndk" >&2
        exit 1
    fi

    mkdir -p "$reference_cache_dir"
    reference_archive="$reference_cache_dir/android-ndk-r27d-linux-x86_64.zip"
    expected_checksum="$reference_sha256  $reference_archive"
    if [[ -f "$reference_archive" ]] && \
       ! printf '%s\n' "$expected_checksum" | sha256sum --check --status; then
        echo "Discarding cached reference archive with an invalid checksum."
        rm -f -- "$reference_archive"
    fi

    if [[ ! -f "$reference_archive" ]]; then
        temporary_archive="$reference_archive.part"
        rm -f -- "$temporary_archive"
        echo "Downloading official Android NDK r27d reference package..."
        curl --fail --location \
            --retry 5 --retry-all-errors --connect-timeout 30 \
            --output "$temporary_archive" "$reference_url"
        printf '%s  %s\n' "$reference_sha256" "$temporary_archive" \
            | sha256sum --check
        mv "$temporary_archive" "$reference_archive"
    fi

    temporary_reference=$(mktemp -d "$reference_cache_dir/.android-ndk-r27d.XXXXXX")
    cleanup_reference() {
        if [[ -n "${temporary_reference:-}" && -d "$temporary_reference" ]]; then
            rm -rf -- "$temporary_reference"
        fi
    }
    trap cleanup_reference EXIT
    unzip -q "$reference_archive" -d "$temporary_reference"
    if ! reference_is_valid "$temporary_reference/$package_name"; then
        echo "error: downloaded archive is not the expected Android NDK r27d package" >&2
        exit 1
    fi
    if [[ -e "$reference_ndk" ]]; then
        echo "error: invalid cached reference path already exists: $reference_ndk" >&2
        exit 1
    fi
    mv "$temporary_reference/$package_name" "$reference_ndk"
    rmdir "$temporary_reference"
    temporary_reference=
    trap - EXIT
fi

export JOBS="$jobs"
export REFERENCE_NDK="$reference_ndk"

echo "Build host: ${PRETTY_NAME:-unknown} ($(uname -m))"
echo "Parallel jobs: $JOBS"
echo "Reference NDK: $REFERENCE_NDK"

build_steps=(
    fetch-sources.sh
    build-host-dependencies.sh
    build-host-runtimes.sh
    build-python.sh
    build-swig.sh
    build-llvm.sh
    build-compiler-rt.sh
    build-host-tools.sh
    build-shader-tools.sh
    build-simpleperf-readelf.sh
    build-simpleperf-report.sh
    build-host-musl.sh
)

for build_step in "${build_steps[@]}"; do
    echo
    echo "==> $build_step"
    "$project_root/scripts/$build_step"
done

# Assembly and packaging are intentionally replaced on every invocation while
# sources and intermediate build trees remain incremental unless CLEAN=1.
rm -rf -- "$project_root/dist/$package_name"
rm -f -- \
    "$project_root/dist/$archive_name" \
    "$project_root/dist/$archive_name.sha256"

echo
echo "==> assemble-ndk.sh"
"$project_root/scripts/assemble-ndk.sh"

echo
echo "==> validate-ndk.sh"
"$project_root/scripts/validate-ndk.sh"

echo
echo "==> package-ndk.sh"
"$project_root/scripts/package-ndk.sh"

archive="$project_root/dist/$archive_name"
checksum="$archive.sha256"
(cd "$project_root/dist" && sha256sum --check "$(basename "$checksum")")
unzip -tq "$archive"
if unzip -Z1 "$archive" | awk -F/ 'NF && $1 != "android-ndk-r27d" { exit 1 }'; then
    :
else
    echo "error: archive contains a path outside $package_name/" >&2
    exit 1
fi

echo
echo "Build complete:"
echo "  $archive"
echo "  $checksum"
