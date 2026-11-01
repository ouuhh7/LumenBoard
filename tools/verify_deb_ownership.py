#!/usr/bin/env python3
"""Verify that every Debian data archive entry is owned by numeric root:root."""

from __future__ import annotations

import argparse
import io
import sys
import tarfile
from pathlib import Path


AR_MAGIC = b"!<arch>\n"


def _data_tar_from_deb(path: Path) -> bytes:
    archive = path.read_bytes()
    if not archive.startswith(AR_MAGIC):
        raise ValueError("file is not a Debian ar archive")

    position = len(AR_MAGIC)
    data_members: list[bytes] = []
    while position < len(archive):
        header = archive[position : position + 60]
        if len(header) != 60 or header[58:60] != b"`\n":
            raise ValueError("malformed ar member header")
        name = header[:16].decode("ascii", "strict").strip().rstrip("/")
        try:
            size = int(header[48:58].decode("ascii", "strict").strip())
        except ValueError as exc:
            raise ValueError(f"invalid size for ar member {name!r}") from exc

        start = position + 60
        end = start + size
        if end > len(archive):
            raise ValueError(f"truncated ar member {name!r}")
        if name.startswith("data.tar"):
            data_members.append(archive[start:end])
        position = end + (size & 1)

    if len(data_members) != 1:
        raise ValueError(f"expected exactly one data.tar member, found {len(data_members)}")
    return data_members[0]


def verify_deb_ownership(path: Path) -> tuple[int, list[str]]:
    data_tar = _data_tar_from_deb(path)
    violations: list[str] = []
    count = 0
    with tarfile.open(fileobj=io.BytesIO(data_tar), mode="r:*") as archive:
        for member in archive.getmembers():
            count += 1
            if member.uid != 0 or member.gid != 0:
                violations.append(
                    f"{member.name}: uid={member.uid} gid={member.gid} "
                    f"(uname={member.uname!r}, gname={member.gname!r})"
                )
    if count == 0:
        raise ValueError("data.tar contains no entries")
    return count, violations


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("deb", type=Path, help="Debian package to inspect")
    args = parser.parse_args(argv)
    try:
        count, violations = verify_deb_ownership(args.deb)
    except (OSError, ValueError, tarfile.TarError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    if violations:
        print("ERROR: package data entries are not numerically owned by root:root:", file=sys.stderr)
        for violation in violations:
            print(f"  {violation}", file=sys.stderr)
        return 1
    print(f"PASS: all {count} data archive entries have numeric owner 0:0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())