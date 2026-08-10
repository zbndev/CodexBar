# CodexBarLinux

Linux GUI for CodexBar. A separate SwiftPM package that depends on the
repository root by path and links the `CodexBarCore` product.

Nothing outside this directory is ever modified — the fork is synced from
upstream, so edits elsewhere would become recurring merge conflicts.

## Requirements

- Swift 6.2+
- gtk4, webkitgtk-6.0

The tray speaks `org.kde.StatusNotifierItem` and `com.canonical.dbusmenu`
directly over GDBus, so `libayatana-appindicator-glib` is no longer a
dependency — it was GPL-3 in an MIT project and shipped on no distribution this
packages for except Arch.

## Build and run

    swift build
    ./.build/debug/CodexBarLinux

## Test

    swift test

## Configuration

Provider credentials and provider-specific settings share CodexBar's CLI
config at `~/.config/codexbar/config.json` (or `CODEXBAR_CONFIG`). The Linux
GUI's display preferences live next to it in `linux-settings.json`. Both are
written with mode `0600`.

The settings window generates provider panes from `CodexBarCore`, so a new
upstream provider receives a basic pane automatically. Linux does not import
browser cookies from system browsers; web providers use the manual Cookie
header until the embedded login flow lands in M4.

## Install

Released artifacts are built by the **Linux Release** workflow, dispatched by
hand with a version. They cover `x86_64` only.

| Artifact | Target |
|---|---|
| `codexbar_<version>_amd64.deb` | Debian 13+, Ubuntu 25.10+ |
| `codexbar-<version>-1.x86_64.rpm` | Fedora 42+ |
| `codexbar-linux-<version>-1-x86_64.pkg.tar.zst` | Arch, via `pacman -U` |
| `CodexBar-<version>-x86_64.AppImage` | any glibc distribution with gtk4 and webkitgtk-6.0 |

The Swift runtime is linked statically, so a package depends only on `gtk4`,
`webkitgtk-6.0`, `glib2`, `libcurl` and `sqlite3`. The Arch package is a
prebuilt one rather than a `PKGBUILD`, so installing it needs no Swift
toolchain from the AUR.

Ubuntu 24.04 is not supported: it predates gtk4 4.18. It is still the *build*
host, because its glibc is the oldest of any candidate and glibc is forward-
but not backward-compatible — see `linux/packaging/NOTES.md`.

The AppImage is a thin bundle and needs the host's gtk4 and webkitgtk-6.0.
Bundling WebKit is not possible: it spawns its helper processes from a path
compiled into the library, and the environment override that would redirect
them is compiled out of distribution builds. `NOTES.md` records the measurement.

## Resources at runtime

Provider brand icons and localization catalogs come from the repository
checkout during development, so a sync from upstream picks up new icons and
translations for free. An installed package has no checkout and reads its own
copy from `/usr/share/codexbar/resources`, made when the package was built.
`LinuxResourceRoot` chooses between them from the executable's own path.
