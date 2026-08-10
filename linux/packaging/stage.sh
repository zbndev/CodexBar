#!/usr/bin/env bash
# Lays out the install tree every package is built from.
#
#   <dest>/usr/lib/codexbar/CodexBarLinux                     the binary
#   <dest>/usr/lib/codexbar/CodexBarLinux_….resources/WebUI/  Bundle.module
#   <dest>/usr/lib/codexbar/CodexBar_CodexBarCore.resources/  bundled JS providers
#   <dest>/usr/lib/codexbar/SweetCookieKit_….resources/       cookie broker
#   <dest>/usr/bin/codexbar                                   symlink
#   <dest>/usr/share/codexbar/resources/                      icons + locales
#   <dest>/usr/share/applications/app.codexbar.linux.desktop
#   <dest>/usr/share/icons/hicolor/512x512/apps/codexbar.png
#   <dest>/usr/share/doc/codexbar/LICENSE
#
# The binary and its resource directory must stay siblings: Bundle.module
# resolves the bundle next to the executable, and /usr/bin/codexbar is a
# symlink precisely so /proc/self/exe still lands in /usr/lib/codexbar.
set -euo pipefail

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <dest>" >&2
    exit 2
fi

dest="$1"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package="$(dirname "$here")"
repository="$(dirname "$package")"

rm -rf "${dest:?}"
mkdir -p "$dest/usr/lib/codexbar" \
         "$dest/usr/bin" \
         "$dest/usr/share/codexbar/resources" \
         "$dest/usr/share/applications" \
         "$dest/usr/share/icons/hicolor/512x512/apps" \
         "$dest/usr/share/doc/codexbar"

"$here/build.sh" "$dest/usr/lib/codexbar"

ln -sf ../lib/codexbar/CodexBarLinux "$dest/usr/bin/codexbar"

# Provider brand icons and localization catalogs, read at runtime through
# LinuxResourceRoot. Copied rather than referenced: a package has no checkout.
upstream="$repository/Sources/CodexBar/Resources"
cp "$upstream"/ProviderIcon-*.svg "$dest/usr/share/codexbar/resources/"
for catalog in "$upstream"/*.lproj; do
    [[ -d "$catalog" ]] || continue
    cp -r "$catalog" "$dest/usr/share/codexbar/resources/"
done

# 512x512 with alpha; icon themes scale down, so one size is enough.
install -Dm644 "$repository/docs/icon.png" \
    "$dest/usr/share/icons/hicolor/512x512/apps/codexbar.png"
install -Dm644 "$here/app.codexbar.linux.desktop" \
    "$dest/usr/share/applications/app.codexbar.linux.desktop"
install -Dm644 "$repository/LICENSE" "$dest/usr/share/doc/codexbar/LICENSE"

icons="$(find "$dest/usr/share/codexbar/resources" -name 'ProviderIcon-*.svg' | wc -l)"
locales="$(find "$dest/usr/share/codexbar/resources" -maxdepth 1 -name '*.lproj' | wc -l)"
echo "$0: staged $icons provider icons and $locales locales into $dest"
if [[ "$icons" -eq 0 || "$locales" -eq 0 ]]; then
    echo "$0: refusing to stage a tree with no icons or no locales" >&2
    exit 1
fi
