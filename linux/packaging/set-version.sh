#!/usr/bin/env bash
# Rewrites BuildVersion.swift so the binary reports the released version.
#
# Run before build.sh in a release job. Leaves a dirty working tree on
# purpose — the change is a build input, not something to commit.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <version>" >&2
    exit 2
fi

version="$1"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "$0: '$version' is not a version like 1.2.3 or 1.2.3-beta.1" >&2
    exit 1
fi

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
file="$(dirname "$here")/Sources/CodexBarLinuxKit/BuildVersion.swift"

cat > "$file" <<SWIFT
/// The version this binary reports.
///
/// Rewritten by \`linux/packaging/set-version.sh\` during a release build; the
/// committed value is what a plain checkout build reports, and it deliberately
/// carries a \`-dev\` suffix so a development binary can never be mistaken for a
/// released one.
public enum BuildVersion {
    public static let marketing = "$version"
}
SWIFT

echo "$0: BuildVersion.marketing = $version"
