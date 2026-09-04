#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
package_root=${1:-$project_root/dist/android-ndk-r27d}
manifest=${2:-$project_root/manifests/ndk-host-archives.tsv}
toolchain="$package_root/toolchains/llvm/prebuilt/linux-aarch64"
archive_list=$(mktemp "$project_root/build/aarch64-host-archives.XXXXXX")
audit_dir=$(mktemp -d "$project_root/build/aarch64-archive-audit.XXXXXX")
bad_members=$(mktemp "$project_root/build/aarch64-bad-members.XXXXXX")
member_list=$(mktemp "$project_root/build/aarch64-archive-members.XXXXXX")
actual_manifest=$(mktemp "$project_root/build/aarch64-archive-manifest.XXXXXX")
cleanup() {
    rm -rf -- "$audit_dir"
    rm -f -- "$archive_list" "$bad_members" "$member_list" "$actual_manifest"
}
trap cleanup EXIT

[[ -f "$manifest" ]] || {
    echo "Missing NDK host archive manifest: $manifest" >&2
    exit 1
}

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
archive_member_count=0
elf_member_count=0

check_member_file() {
    local archive=$1 member=$2 occurrence=$3 path=$4 description
    if ! description=$(aarch64-linux-gnu-objdump -f -- "$path" 2>&1) ||
       ! grep -Fq 'file format elf64-littleaarch64' <<< "$description" ||
       ! grep -Eq '^architecture: aarch64,' <<< "$description"; then
        printf '%s(%s occurrence %s): %s\n' \
            "$archive" "$member" "$occurrence" "$description" >> "$bad_members"
        return
    fi
    elf_member_count=$((elf_member_count + 1))
}

while IFS= read -r archive; do
    find "$audit_dir" -mindepth 1 -delete
    absolute_archive=$(realpath "$archive")
    if ! aarch64-linux-gnu-ar t "$absolute_archive" > "$member_list"; then
        echo "Invalid AArch64 host archive: $archive" >&2
        exit 1
    fi
    member_count=$(wc -l < "$member_list")
    if (( member_count == 0 )); then
        echo "AArch64 host archive contains no members: $archive" >&2
        exit 1
    fi
    archive_member_count=$((archive_member_count + member_count))
    relative=${archive#"$package_root/"}
    member_digest=$(sha256sum "$member_list" | awk '{print $1}')
    printf '%s\t%s\t%s\n' "$relative" "$member_count" "$member_digest" \
        >> "$actual_manifest"

    # A normal extraction leaves the final occurrence when an archive contains
    # duplicate member names. Check that unique set first.
    (cd "$audit_dir" && aarch64-linux-gnu-ar x "$absolute_archive")
    while IFS= read -r -d '' member_path; do
        member_name=${member_path#"$audit_dir/"}
        check_member_file "$archive" "$member_name" final "$member_path"
    done < <(find "$audit_dir" -type f -print0)

    # GNU ar overwrites earlier duplicate names during normal extraction.
    # Extract and inspect every earlier occurrence explicitly with the N
    # modifier so no archive member is skipped.
    duplicate_index=0
    while read -r occurrence_count member_name; do
        (( occurrence_count > 1 )) || continue
        for (( occurrence=1; occurrence < occurrence_count; occurrence++ )); do
            duplicate_dir="$audit_dir/.duplicate-$duplicate_index"
            mkdir "$duplicate_dir"
            (cd "$duplicate_dir" && \
                aarch64-linux-gnu-ar xN "$occurrence" "$absolute_archive" "$member_name")
            mapfile -d '' -t extracted_members < <(find "$duplicate_dir" -type f -print0)
            if (( ${#extracted_members[@]} != 1 )); then
                echo "error: failed to extract $member_name occurrence $occurrence from $archive" >&2
                exit 1
            fi
            check_member_file "$archive" "$member_name" "$occurrence" \
                "${extracted_members[0]}"
            duplicate_index=$((duplicate_index + 1))
        done
    done < <(LC_ALL=C sort "$member_list" | uniq -c)
    archive_count=$((archive_count + 1))
done < "$archive_list"

if ! diff -u <(grep -Ev '^[[:space:]]*(#|$)' "$manifest") \
    "$actual_manifest"; then
    echo "AArch64 host archive member inventory differs from the pinned manifest" >&2
    exit 1
fi

if [[ -s "$bad_members" ]]; then
    echo "Invalid or non-AArch64 members found in host archives:" >&2
    cat "$bad_members" >&2
    exit 1
fi

echo "aarch64_host_archives=$archive_count"
echo "aarch64_archive_members=$archive_member_count"
echo "aarch64_elf_archive_members=$elf_member_count"
