#!/usr/bin/env bash
# Packages the staged tree as an AppImage.
#
# Deliberately a *thin* bundle: the staged tree plus AppRun, with gtk4 and
# webkitgtk-6.0 coming from the host. A self-contained bundle was built and
# measured first, and it cannot work — WebKitGTK spawns its helper processes
# from a path compiled into the library, and the `WEBKIT_EXEC_PATH` override is
# compiled out of distribution builds, so the bundled WebKit is never reached.
# NOTES.md records the exact failure.
#
# That also means linuxdeploy is not used at all: its whole job is walking
# NEEDED entries and copying libraries in, which is precisely what must not
# happen here. appimagetool packages the AppDir as-is.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <staged-root> <version> <output-dir>" >&2
    exit 2
fi

root="$1"
version="$2"
output="$3"
arch="${CODEXBAR_APPIMAGE_ARCH:-x86_64}"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

tools="${CODEXBAR_APPIMAGE_TOOLS:-$(mktemp -d)}"
mkdir -p "$tools"
if [[ ! -x "$tools/appimagetool" ]]; then
    curl -fsSL -o "$tools/appimagetool" \
        "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${arch}.AppImage"
    chmod +x "$tools/appimagetool"
fi

# appimagetool is itself an AppImage, and mounting one needs FUSE. Neither a
# container nor a GitHub runner reliably has it, so tell it to unpack itself.
export APPIMAGE_EXTRACT_AND_RUN=1

appdir="$(mktemp -d)/AppDir"
mkdir -p "$appdir"
cp -r "$root/." "$appdir/"

install -Dm755 "$here/AppRun" "$appdir/AppRun"
# appimagetool wants the desktop entry and icon at the AppDir root.
install -Dm644 "$root/usr/share/applications/app.codexbar.linux.desktop" \
    "$appdir/app.codexbar.linux.desktop"
install -Dm644 "$root/usr/share/icons/hicolor/512x512/apps/codexbar.png" \
    "$appdir/codexbar.png"
cp "$appdir/codexbar.png" "$appdir/.DirIcon"

mkdir -p "$output"
artifact="$output/CodexBar-${version}-${arch}.AppImage"
ARCH="$arch" "$tools/appimagetool" --no-appstream "$appdir" "$artifact" >/dev/null
echo "$artifact"
