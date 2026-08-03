#!/usr/bin/env bash
# Turns a staged tree into a .deb.
#
# Dependencies are declared by hand rather than by dh_shlibdeps: the Swift
# runtime is linked statically, so the list is short, and the t64 alternatives
# let one package serve both Debian 13 and Ubuntu 25.10+. Every name here comes
# from the measured DT_NEEDED set in NOTES.md — do not add one from memory.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <staged-root> <version> <output-dir>" >&2
    exit 2
fi

root="$1"
version="$2"
output="$3"
arch="${CODEXBAR_DEB_ARCH:-amd64}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

cp -r "$root/." "$work/"
mkdir -p "$work/DEBIAN"

installed_kb="$(du -sk "$work/usr" | cut -f1)"

cat > "$work/DEBIAN/control" <<CONTROL
Package: codexbar
Version: $version
Section: utils
Priority: optional
Architecture: $arch
Depends: libgtk-4-1 (>= 4.18), libwebkitgtk-6.0-4, libglib2.0-0t64 | libglib2.0-0, libcurl4t64 | libcurl4, libsqlite3-0
Installed-Size: $installed_kb
Maintainer: CodexBar for Linux <noreply@users.noreply.github.com>
Homepage: https://github.com/zbndev/CodexBar
Description: AI coding usage in your tray
 CodexBar shows usage, quota and spend for AI coding providers in the
 system tray. This is the Linux GUI build.
CONTROL

# dpkg refuses to install a package whose symlinks point outside it, so the
# relative /usr/bin symlink from stage.sh is required, not cosmetic.
mkdir -p "$output"
artifact="$output/codexbar_${version}_${arch}.deb"
dpkg-deb --build --root-owner-group "$work" "$artifact" >/dev/null
echo "$artifact"
