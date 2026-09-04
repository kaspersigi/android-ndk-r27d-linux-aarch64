#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0

set -euo pipefail

allow_relocatable=0
if [[ "${1:-}" == "--allow-relocatable" ]]; then
    allow_relocatable=1
    shift
fi

if (( $# == 0 )); then
    echo "usage: $0 [--allow-relocatable] <AArch64 ELF> [...]" >&2
    exit 2
fi

command -v aarch64-linux-gnu-objdump >/dev/null 2>&1 || {
    echo "error: aarch64-linux-gnu-objdump is required" >&2
    exit 1
}

for path in "$@"; do
    [[ -f "$path" ]] || {
        echo "error: AArch64 ELF is not a regular file: $path" >&2
        exit 1
    }

    if ! description=$(aarch64-linux-gnu-objdump -f -- "$path" 2>&1); then
        echo "error: invalid or truncated AArch64 ELF: $path" >&2
        printf '%s\n' "$description" >&2
        exit 1
    fi
    grep -Fq 'file format elf64-littleaarch64' <<< "$description" &&
        grep -Eq '^architecture: aarch64,' <<< "$description" || {
        echo "error: unexpected ELF format or machine: $path" >&2
        printf '%s\n' "$description" >&2
        exit 1
    }
    if (( ! allow_relocatable )) &&
       ! grep -Eq '(^|[[:space:],])(EXEC_P|DYNAMIC)([[:space:],]|$)' \
           <<< "$description"; then
        echo "error: host ELF is neither executable nor shared: $path" >&2
        printf '%s\n' "$description" >&2
        exit 1
    fi
done
