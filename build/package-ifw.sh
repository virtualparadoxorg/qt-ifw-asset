#!/usr/bin/env bash
# Pack an IFW install prefix (from build-ifw.sh) into the archive that is published:
#   bin/  licenses/  VERSIONS  README.txt
# at the archive root, so it unpacks straight into the target folder.
#
# Usage: package-ifw.sh <prefix> <archive>
#   <archive> ends in .tar.gz (macOS, Linux; keeps the executable bits) or .zip (Windows).
set -euo pipefail

fail() {
  echo "package-ifw: $1" >&2
  exit 1
}

[ "$#" -eq 2 ] || { echo "usage: package-ifw.sh <prefix> <archive>" >&2; exit 2; }
prefix=$(cd "$1" && pwd)
repo=$(cd "$(dirname "$0")/.." && pwd)
[ -d "$prefix/bin" ] && [ -d "$prefix/licenses" ] && [ -f "$prefix/VERSIONS" ] ||
  fail "$prefix is not a build-ifw.sh prefix (bin/, licenses/, VERSIONS)"

cp "$repo/build/archive-readme.txt" "$prefix/README.txt"
mkdir -p "$(dirname "$2")"
out=$(cd "$(dirname "$2")" && pwd)/$(basename "$2")
rm -f "$out"
case "$out" in
  *.tar.gz) tar -czf "$out" -C "$prefix" bin licenses VERSIONS README.txt ;;
  *.zip)
    if command -v 7z >/dev/null; then
      (cd "$prefix" && 7z a -tzip -bd -bso0 "$out" bin licenses VERSIONS README.txt)
    else
      (cd "$prefix" && zip -qr "$out" bin licenses VERSIONS README.txt)
    fi
    ;;
  *) fail "archive must end in .tar.gz or .zip: $2" ;;
esac
ls -l "$out"
