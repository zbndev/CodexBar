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

# Never run this under fakeroot: swift-package segfaults there. Every packager
# reads a tree this script has already produced, so nothing needs to.
swift build --package-path "$package" -c release --static-swift-stdlib

binary="$package/.build/release/CodexBarLinux"
# SwiftPM on Linux emits a plain directory per resource-bearing target, not a
# .bundle; each one resolves next to the executable. Every dependency's bundle
# has to ship, not just this package's: CodexBarCore's holds the bundled
# JavaScript providers (z.ai, xAI, Poe, …) and the plugin prelude, and without
# it every JS provider fails with "CodexBarCore resource bundle is missing".
resources=("$package"/.build/release/*.resources)

if [[ ! -e "$binary" ]]; then
    echo "$0: expected build product missing: $binary" >&2
    exit 1
fi
for required in CodexBar_CodexBarCore CodexBarLinux_CodexBarLinuxKit; do
    if [[ ! -d "$package/.build/release/$required.resources" ]]; then
        echo "$0: expected build product missing: $required.resources" >&2
        exit 1
    fi
done

mkdir -p "$output"
install -Dm755 "$binary" "$output/CodexBarLinux"
for resource in "${resources[@]}"; do
    rm -rf "${output:?}/$(basename "$resource")"
    cp -r "$resource" "$output/"
done
