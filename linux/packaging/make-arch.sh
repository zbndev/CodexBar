#!/usr/bin/env bash
# Turns a staged tree into a pacman package, using a native makepkg when the
# host has one and an archlinux container otherwise — the release host is
# Ubuntu, and Arch has no hosted runner.
#
# The recipe is generated here rather than committed as a PKGBUILD, for the
# same reason make-deb.sh writes DEBIAN/control and make-rpm.sh writes a .spec:
# it is metadata for one artifact, not a second description of the build that
# can drift from this one. A committed PKGBUILD pointed at a release tag, and
# the tag it named drifted a commit behind the recipe that read it.
#
# The recipe builds nothing, for two independent reasons. The binary must come
# from the same staged tree the .deb and .rpm are cut from, because glibc is
# forward- but not backward-compatible and one built on Arch (2.44) dies on
# Debian 13. And makepkg runs package() under fakeroot, where swift-package
# segfaults — so a recipe that called stage.sh would crash even on Arch.
#
# Depends are Arch package names, recorded in NOTES.md.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <staged-root> <version> <output-dir>" >&2
    exit 2
fi

root="$(cd "$1" && pwd)"
version="$2"
output="$3"
arch="${CODEXBAR_PACMAN_ARCH:-x86_64}"
image="${CODEXBAR_ARCH_IMAGE:-archlinux:base-devel}"
# Matches the .deb's Maintainer; without it makepkg stamps "Unknown Packager".
packager="CodexBar for Linux <noreply@users.noreply.github.com>"

# pacman forbids '-' in pkgver and has no equivalent of rpm's '~', so a
# prerelease like 1.2.3-rc.1 becomes 1.2.3_rc.1 and vercmp orders it *after*
# 1.2.3 rather than before. Harmless for `pacman -U`, which is how this
# artifact is installed; see NOTES.md.
pkgver="${version//-/_}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/out" "$work/root"

# The tree travels next to the recipe so the native and container paths are
# identical: package() reads it through $startdir either way.
cp -a "$root/." "$work/root/"

cat > "$work/PKGBUILD" <<PKGBUILD
pkgname=codexbar-linux
pkgver=$pkgver
pkgrel=1
pkgdesc="AI coding usage in your tray (Linux GUI for CodexBar)"
arch=('$arch')
url="https://github.com/zbndev/CodexBar-Linux"
license=('MIT')
depends=('gtk4' 'webkitgtk-6.0' 'glib2' 'curl' 'sqlite')
# The Swift runtime is linked statically, so stripping is the riskier of the
# two options and a separate debug package would have nothing to carry.
options=('!strip' '!debug')
source=()

package() {
    cp -a "\$startdir/root/." "\$pkgdir/"
    # Free under fakeroot, and without it every file would carry the build
    # user's uid into the package.
    chown -R root:root "\$pkgdir"
}
PKGBUILD

# -d skips dependency checks: this is a cross-packaging host, and the recipe
# builds nothing that could need them.
if [[ "${CODEXBAR_ARCH_FORCE_CONTAINER:-0}" != "1" ]] && command -v makepkg >/dev/null; then
    (cd "$work" && PKGDEST="$work/out" PACKAGER="$packager" makepkg -d --noconfirm >/dev/null)
else
    # makepkg refuses to run as root, so the container gets a build user with
    # the caller's uid — the artifact then comes back out owned by the caller.
    cat > "$work/run.sh" <<'RUNNER'
set -euo pipefail
uid="$1"
packager="$2"
useradd -m -u "$uid" builder 2>/dev/null || useradd -m builder
chown -R builder /build
cd /build
# runuser rather than `su -c`, so the packager string arrives as one argv
# element instead of going through a second round of shell quoting.
runuser -u builder -- env PKGDEST=/build/out PACKAGER="$packager" \
    makepkg -d --noconfirm >/dev/null
RUNNER
    docker run --rm -v "$work:/build" "$image" \
        bash /build/run.sh "$(id -u)" "$packager"
fi

mkdir -p "$output"
built="$(find "$work/out" -name '*.pkg.tar.zst' -print -quit)"
if [[ -z "$built" ]]; then
    echo "$0: makepkg produced no package" >&2
    exit 1
fi
artifact="$output/$(basename "$built")"
mv "$built" "$artifact"
echo "$artifact"
