#!/usr/bin/env bash
# Turns a staged tree into an .rpm, built on Debian/Ubuntu.
#
# AutoReqProv is off on purpose: rpmbuild running on a Debian host cannot
# resolve Fedora sonames, and would emit either nothing or wrong names. The
# Requires below are Fedora package names, recorded in NOTES.md.
set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "usage: $0 <staged-root> <version> <output-dir>" >&2
    exit 2
fi

root="$(cd "$1" && pwd)"
version="$2"
output="$3"
arch="${CODEXBAR_RPM_ARCH:-x86_64}"

# rpm refuses a Version containing '-'; a prerelease like 1.2.3-rc.1 becomes
# 1.2.3~rc.1, which rpm also orders correctly as earlier than 1.2.3.
rpm_version="${version//-/\~}"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

cat > "$work/SPECS/codexbar.spec" <<SPEC
Name:           codexbar
Version:        $rpm_version
Release:        1
Summary:        AI coding usage in your tray
License:        MIT
URL:            https://github.com/zbndev/CodexBar
BuildArch:      $arch
AutoReqProv:    no
Requires:       gtk4 >= 4.18
Requires:       webkitgtk6.0
Requires:       glib2
Requires:       libcurl
Requires:       sqlite-libs

%description
CodexBar shows usage, quota and spend for AI coding providers in the system
tray. This is the Linux GUI build.

%install
cp -a $root/usr %{buildroot}/

%files
/usr/bin/codexbar
/usr/lib/codexbar
/usr/share/codexbar
/usr/share/applications/app.codexbar.linux.desktop
/usr/share/icons/hicolor/512x512/apps/codexbar.png
%license /usr/share/doc/codexbar/LICENSE

%changelog
SPEC

rpmbuild --define "_topdir $work" \
         --define "_build_id_links none" \
         -bb "$work/SPECS/codexbar.spec" >/dev/null

mkdir -p "$output"
built="$(find "$work/RPMS" -name '*.rpm' -print -quit)"
if [[ -z "$built" ]]; then
    echo "$0: rpmbuild produced no package" >&2
    exit 1
fi
artifact="$output/$(basename "$built")"
mv "$built" "$artifact"
echo "$artifact"
