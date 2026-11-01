#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "Usage: $0 path/to/package.deb" >&2
  exit 2
fi

deb="$1"
if [[ ! -f "$deb" ]]; then
  echo "ERROR: package does not exist: $deb" >&2
  exit 2
fi
for command in dpkg-deb python3; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR: required command is unavailable: $command" >&2
    exit 2
  fi
done

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/lumenboard-deb-owner.XXXXXX")"
normalized="${deb}.owner-normalized.$$"
trap 'rm -rf "$work_dir"; rm -f "$normalized"' EXIT

mkdir -p "$work_dir/root"
dpkg-deb --raw-extract "$deb" "$work_dir/root"
dpkg-deb --root-owner-group -Zxz -z9 --build "$work_dir/root" "$normalized"
python3 "$project_dir/tools/verify_deb_ownership.py" "$normalized"

# Replace the original only after the normalized archive has passed verification.
mv -f "$normalized" "$deb"
python3 "$project_dir/tools/verify_deb_ownership.py" "$deb"