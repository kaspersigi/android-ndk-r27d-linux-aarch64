#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
temporary_dir=$(mktemp -d "${TMPDIR:-/tmp}/ndk-elf-test.XXXXXX")
cleanup() {
    rm -rf -- "$temporary_dir"
}
trap cleanup EXIT

printf '%s\n' 'int main(void) { return 0; }' |
    aarch64-linux-gnu-gcc -x c - -o "$temporary_dir/valid"
"$project_root/scripts/check-aarch64-elf.sh" "$temporary_dir/valid"

printf '%s\n' 'int value;' |
    aarch64-linux-gnu-gcc -x c -c - -o "$temporary_dir/relocatable.o"
if "$project_root/scripts/check-aarch64-elf.sh" "$temporary_dir/relocatable.o" \
    >"$temporary_dir/stdout" 2>"$temporary_dir/stderr"; then
    echo "error: relocatable object unexpectedly passed host ELF validation" >&2
    exit 1
fi
"$project_root/scripts/check-aarch64-elf.sh" --allow-relocatable \
    "$temporary_dir/relocatable.o"

head -c 64 "$temporary_dir/valid" > "$temporary_dir/truncated"
if "$project_root/scripts/check-aarch64-elf.sh" "$temporary_dir/truncated" \
    >"$temporary_dir/stdout" 2>"$temporary_dir/stderr"; then
    echo "error: truncated ELF unexpectedly passed validation" >&2
    exit 1
fi
grep -Fq 'invalid or truncated AArch64 ELF' "$temporary_dir/stderr"

echo "AArch64 ELF structural validation test passed."
