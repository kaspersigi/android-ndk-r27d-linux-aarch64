#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ndk-archive-test.XXXXXX")
cleanup() {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

package_root="$temporary_dir/android-ndk-r27d"
archive="$package_root/prebuilt/linux-aarch64/lib/probe.a"
compiler_rt_dir="$package_root/toolchains/llvm/prebuilt/linux-aarch64/"
compiler_rt_dir+="lib/clang/18/lib/aarch64-unknown-linux-gnu"
mkdir -p \
    "$(dirname "$archive")" \
    "$package_root/toolchains/llvm/prebuilt/linux-aarch64/lib/aarch64-unknown-linux-gnu" \
    "$compiler_rt_dir"
printf '%s\n' 'int probe;' |
    aarch64-linux-gnu-gcc -x c -c - -o "$temporary_dir/probe.o"
aarch64-linux-gnu-ar rcS "$archive" "$temporary_dir/probe.o"

write_manifest() {
    aarch64-linux-gnu-ar t "$archive" > "$temporary_dir/members"
    printf '%s\t%s\t%s\n' \
        'prebuilt/linux-aarch64/lib/probe.a' \
        "$(wc -l < "$temporary_dir/members")" \
        "$(sha256sum "$temporary_dir/members" | awk '{print $1}')" \
        > "$temporary_dir/manifest.tsv"
}

install_archive_member() {
    rm -f -- "$archive"
    aarch64-linux-gnu-ar rcS "$archive" "$1"
    write_manifest
}

write_manifest

"$project_root/scripts/check-aarch64-host-archives.sh" \
    "$package_root" "$temporary_dir/manifest.tsv" >/dev/null

printf '%s\n' 'int main(void) { return 0; }' |
    aarch64-linux-gnu-gcc -x c -no-pie - -o "$temporary_dir/executable"
printf '%s\n' 'int shared_probe(void) { return 0; }' |
    aarch64-linux-gnu-gcc -x c -fPIC -shared - -o "$temporary_dir/shared.so"
for non_relocatable in executable shared.so; do
    install_archive_member "$temporary_dir/$non_relocatable"
    if "$project_root/scripts/check-aarch64-host-archives.sh" \
        "$package_root" "$temporary_dir/manifest.tsv" \
        >"$temporary_dir/stdout" 2>"$temporary_dir/stderr"; then
        echo "error: $non_relocatable archive member unexpectedly passed validation" >&2
        exit 1
    fi
    grep -Fq 'Invalid, non-relocatable, or non-AArch64 members' \
        "$temporary_dir/stderr"
done

install_archive_member "$temporary_dir/probe.o"

printf 'BAD!' | dd of="$archive" bs=1 seek=68 conv=notrunc status=none
if "$project_root/scripts/check-aarch64-host-archives.sh" \
    "$package_root" "$temporary_dir/manifest.tsv" \
    >"$temporary_dir/stdout" 2>"$temporary_dir/stderr"; then
    echo "error: archive with a truncated member unexpectedly passed validation" >&2
    exit 1
fi
grep -Fq 'Invalid, non-relocatable, or non-AArch64 members' \
    "$temporary_dir/stderr"

rm -f -- "$archive"
aarch64-linux-gnu-ar rcs "$archive"
if "$project_root/scripts/check-aarch64-host-archives.sh" \
    "$package_root" "$temporary_dir/manifest.tsv" \
    >"$temporary_dir/stdout" 2>"$temporary_dir/stderr"; then
    echo "error: empty archive unexpectedly passed validation" >&2
    exit 1
fi
grep -Fq 'contains no members' "$temporary_dir/stderr"

echo "AArch64 host archive inventory test passed."
