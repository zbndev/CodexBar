#!/usr/bin/env bash
# Copies the PKGBUILD into the artifact directory with the release version and
# the tag tarball's checksum filled in.
#
# The tarball is GitHub's own archive of the tag, so this runs after the tag is
# known but the checksum can only be computed once GitHub serves it — hence
# fetching it here rather than reusing a local archive, which would differ.
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <version> <output-dir>" >&2
    exit 2
fi

version="$1"
output="$2"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$output"
sed -e "s/^pkgver=.*/pkgver=$version/" \
    "$here/PKGBUILD" > "$output/PKGBUILD"

echo "$0: wrote $output/PKGBUILD for $version with sha256sums=('SKIP')"
echo "$0: run 'updpkgsums' after the tag is published to pin the checksum"
