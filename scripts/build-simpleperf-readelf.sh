#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
llvm_lib_dir="$project_root/build/llvm-linux-aarch64/lib"
install_dir="$project_root/out/simpleperf-linux-aarch64"
output="$install_dir/libsimpleperf_readelf.a"

# This is the exact LLVM component set selected by r27d's
# LibSimpleperfReadElfBuilder (`llvm-config --libs object --link-static`).
llvm_libraries=(
    libLLVMDemangle.a
    libLLVMSupport.a
    libLLVMBitstreamReader.a
    libLLVMTargetParser.a
    libLLVMBinaryFormat.a
    libLLVMRemarks.a
    libLLVMCore.a
    libLLVMBitReader.a
    libLLVMDebugInfoCodeView.a
    libLLVMMC.a
    libLLVMAsmParser.a
    libLLVMIRReader.a
    libLLVMMCParser.a
    libLLVMTextAPI.a
    libLLVMObject.a
)

for library in "${llvm_libraries[@]}"; do
    if [[ ! -f "$llvm_lib_dir/$library" ]]; then
        echo "Missing LLVM library: $llvm_lib_dir/$library" >&2
        exit 1
    fi
done

mkdir -p "$install_dir" "$project_root/build"
temporary_root=$(mktemp -d "$project_root/build/.simpleperf-readelf.XXXXXX")
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

for library in "${llvm_libraries[@]}"; do
    extract_dir="$temporary_root/${library%.a}"
    mkdir "$extract_dir"
    (
        cd "$extract_dir"
        aarch64-linux-gnu-ar -x "$llvm_lib_dir/$library"
    )
done

rm -f -- "$output"
(
    cd "$temporary_root"
    # Keep separate extraction directories: LLVM component archives contain
    # repeated object basenames and r27d intentionally preserves all of them.
    aarch64-linux-gnu-ar -cqs "$output" ./*/*
)

file "$output"
printf 'members=%s\n' "$(aarch64-linux-gnu-ar t "$output" | wc -l)"
