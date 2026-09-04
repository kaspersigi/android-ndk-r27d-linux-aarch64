#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
dist_dir="$project_root/dist"
package_name=android-ndk-r27d
package_root="$dist_dir/$package_name"
archive_name=android-ndk-r27d-linux.zip
archive="$dist_dir/$archive_name"
checksum="$archive.sha256"

if [[ ! -d "$package_root" ]]; then
    echo "Missing assembled package: $package_root" >&2
    exit 1
fi
if [[ -e "$archive" || -e "$checksum" ]]; then
    echo "Archive or checksum already exists: $archive" >&2
    exit 1
fi

temporary_root=$(mktemp -d "$dist_dir/.package-linux.XXXXXX")
cleanup() {
    if [[ -n "${temporary_root:-}" && -d "$temporary_root" ]]; then
        rm -rf -- "$temporary_root"
    fi
}
trap cleanup EXIT

(
    cd "$dist_dir"
    export LC_ALL=C
    export TZ=UTC
    find "$package_name" -exec touch -h -d '2008-01-01 00:00:00 UTC' {} +
    find "$package_name" -print | sort | \
        zip -q -X -y "$temporary_root/$archive_name" -@
)
mv "$temporary_root/$archive_name" "$archive"
python3 -B "$project_root/scripts/check-zip-metadata.py" "$archive"
(cd "$dist_dir" && sha256sum "$archive_name") > "$checksum"
rmdir "$temporary_root"
temporary_root=
trap - EXIT

cat "$checksum"
