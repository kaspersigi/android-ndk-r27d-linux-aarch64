#!/usr/bin/env python3
"""Require deterministic timestamps and stripped extra fields in a ZIP."""

from __future__ import annotations

import sys
from pathlib import Path
from zipfile import BadZipFile, ZipFile


EXPECTED_TIMESTAMP = (2008, 1, 1, 0, 0, 0)


def main() -> int:
    if len(sys.argv) != 2:
        print(f"usage: {sys.argv[0]} <archive.zip>", file=sys.stderr)
        return 2
    archive = Path(sys.argv[1])
    try:
        with ZipFile(archive) as package:
            entries = package.infolist()
    except (OSError, BadZipFile) as error:
        print(f"error: cannot inspect ZIP metadata: {error}", file=sys.stderr)
        return 1
    if not entries:
        print(f"error: ZIP archive is empty: {archive}", file=sys.stderr)
        return 1
    bad_timestamps = [
        entry.filename for entry in entries if entry.date_time != EXPECTED_TIMESTAMP
    ]
    extra_fields = [entry.filename for entry in entries if entry.extra]
    if bad_timestamps or extra_fields:
        for path in bad_timestamps[:20]:
            print(f"error: non-deterministic ZIP timestamp: {path}", file=sys.stderr)
        for path in extra_fields[:20]:
            print(f"error: unexpected ZIP extra field: {path}", file=sys.stderr)
        return 1
    print(f"zip_entries_with_deterministic_metadata={len(entries)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
