#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_root=${1:-$project_root/dist/android-ndk-r27d}
toolchain="$package_root/toolchains/llvm/prebuilt/linux-aarch64"
archive_list=$(mktemp "$project_root/build/aarch64-host-archives.XXXXXX")
audit_dir=$(mktemp -d "$project_root/build/aarch64-archive-audit.XXXXXX")
bad_members=$(mktemp "$project_root/build/aarch64-bad-members.XXXXXX")
cleanup() {
    rm -rf -- "$audit_dir"
    rm -f -- "$archive_list" "$bad_members"
}
trap cleanup EXIT

for required in "$toolchain" "$package_root/prebuilt/linux-aarch64/lib"; do
    if [[ ! -d "$required" ]]; then
        echo "Missing AArch64 host archive root: $required" >&2
        exit 1
    fi
done

{
    find "$package_root/prebuilt/linux-aarch64/lib" \
        -maxdepth 1 -type f -name '*.a'
    find "$toolchain/lib" -maxdepth 1 -type f -name '*.a'
    find "$toolchain/lib/aarch64-unknown-linux-gnu" \
        -maxdepth 1 -type f -name '*.a'
    find "$toolchain/lib/clang/18/lib/aarch64-unknown-linux-gnu" \
        -maxdepth 1 -type f -name '*.a'
} | sort -u > "$archive_list"

: > "$bad_members"
archive_count=0
elf_member_count=0
while IFS= read -r archive; do
    find "$audit_dir" -mindepth 1 -delete
    absolute_archive=$(realpath "$archive")
    (cd "$audit_dir" && aarch64-linux-gnu-ar x "$absolute_archive")
    while IFS= read -r description; do
        elf_member_count=$((elf_member_count + 1))
        if [[ "$description" != *'ARM aarch64'* ]]; then
            printf '%s: %s\n' "$archive" "$description" >> "$bad_members"
        fi
    done < <(find "$audit_dir" -type f -print0 | xargs -0 -r file | rg 'ELF ' || true)
    archive_count=$((archive_count + 1))
done < "$archive_list"

if [[ -s "$bad_members" ]]; then
    echo "Non-AArch64 ELF members found in host archives:" >&2
    cat "$bad_members" >&2
    exit 1
fi

echo "aarch64_host_archives=$archive_count"
echo "aarch64_elf_archive_members=$elf_member_count"
