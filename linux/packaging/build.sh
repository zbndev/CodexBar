#!/usr/bin/env bash
# Builds the release binary with a statically linked Swift runtime and copies
# it, with its resource bundle, into the output directory.
#
# The Swift runtime is static so a package depends only on C libraries; see
# linux/packaging/NOTES.md for the measured dependency set.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <output-dir>" >&2
    exit 2
fi

output="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"

# CODEXBAR_SKIP_BUILD=1 stages products that already exist instead of building.
# makepkg runs package() under fakeroot, where swift-package segfaults, so the
# PKGBUILD builds in build() and only stages here. The existence checks below
# then carry the weight: a missing product fails loudly rather than silently
# packaging nothing.
if [[ "${CODEXBAR_SKIP_BUILD:-0}" != "1" ]]; then
    swift build --package-path "$package" -c release --static-swift-stdlib
fi

binary="$package/.build/release/CodexBarLinux"
# SwiftPM on Linux emits a plain directory, not a .bundle; Bundle.module
# resolves it next to the executable.
resources="$package/.build/release/CodexBarLinux_CodexBarLinuxKit.resources"

for path in "$binary" "$resources"; do
    if [[ ! -e "$path" ]]; then
        echo "$0: expected build product missing: $path" >&2
        exit 1
    fi
done

mkdir -p "$output"
install -Dm755 "$binary" "$output/CodexBarLinux"
rm -rf "${output:?}/$(basename "$resources")"
cp -r "$resources" "$output/"
