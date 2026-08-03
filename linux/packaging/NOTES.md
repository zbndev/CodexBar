# Packaging notes

Measured facts the packaging scripts depend on. Re-measure before changing a
dependency list; do not edit these from memory.

## Build floor

- Swift: 6.3.3
- Development machine: gtk4 4.22.4, webkitgtk-6.0 2.52.5 (Arch)
- Measured for reference — `ubuntu:24.04`: gtk4 **4.14.5**, webkitgtk-6.0 **2.52.3**
- Verdict: **the floor is Debian 13 / gtk4 4.18.** Ubuntu 24.04 is not
  supported.

### Why the floor is not Ubuntu 24.04

This was a scope decision, not a measured compile failure: the project targets
current distributions, and an LTS old enough to predate gtk4 4.18 is not worth
constraining the code for. Supported set is Debian 13+, Fedora 42+, Arch, and
Ubuntu 25.10+.

Worth recording because it would otherwise look like an oversight: 24.04 was
also the one image where the check was awkward to run at all. It ships no
`libayatana-appindicator-glib-dev` — only the GTK-2 and GTK-3 subpackages of
`libayatana-appindicator` — so before M6.3 removed that system-library target,
SwiftPM could not resolve the `ayatana-appindicator-glib` pkg-config module and
the package failed to configure before a single source file was read. That
availability wall is exactly what M6.3 exists to remove.

The verified-good versions are gtk4 4.22.4 / webkitgtk-6.0 2.52.5 on the
development machine, plus whatever `debian:13` carries — the `.deb` install
test in M6.8 runs there, so the floor claim is checked on every release.

## Runtime dependencies of the release binary

`--static-swift-stdlib` takes effect: no `libswiftCore.so`,
`libswift_Concurrency.so` or `libFoundation.so` appears in `ldd`. The Swift
runtime is inside the 144 MB binary.

Direct `DT_NEEDED` entries are what a `Depends:` line has to cover; `ldd`
prints the whole transitive closure, most of which arrives through gtk4 and
webkitgtk anyway. Measured with
`readelf -d .build/release/CodexBarLinux | grep NEEDED`:

```
ld-linux-x86-64.so.2
libcairo-gobject.so.2
libcairo.so.2
libc.so.6
libcurl.so.4
libgcc_s.so.1
libgdk_pixbuf-2.0.so.0
libgio-2.0.so.0
libglib-2.0.so.0
libgmodule-2.0.so.0
libgobject-2.0.so.0
libgraphene-1.0.so.0
libgtk-4.so.1
libharfbuzz.so.0
libjavascriptcoregtk-6.0.so.1
libm.so.6
libpango-1.0.so.0
libpangocairo-1.0.so.0
libsoup-3.0.so.0
libsqlite3.so.0
libstdc++.so.6
libvulkan.so.1
libwebkitgtk-6.0.so.4
```

Measured after M6.3. Before it the list also carried
`libayatana-appindicator-glib.so.2`; that name being gone is the check that the
tray really is served in-process rather than through the library.

`libsqlite3.so.0` is the surprise: nothing in `linux/Sources` mentions SQLite,
it comes from the statically linked Foundation. Every distribution's
webkitgtk package happens to pull it in transitively, but a `Depends:` that
relies on that is a guess — it is declared explicitly instead.

Everything else on the list arrives with gtk4 or webkitgtk-6.0, which is why
the declared dependency set is four names rather than twenty-three.

## Distribution package names

| Library | Debian/Ubuntu | Fedora |
|---|---|---|
| gtk4 | libgtk-4-1 | gtk4 |
| webkitgtk-6.0 | libwebkitgtk-6.0-4 | webkitgtk6.0 |
| glib2 | libglib2.0-0t64 \| libglib2.0-0 | glib2 |
| curl | libcurl4t64 \| libcurl4 | libcurl |
| sqlite3 | libsqlite3-0 | sqlite-libs |

## Install layout

```
<dest>/usr/lib/codexbar/CodexBarLinux                     the binary
<dest>/usr/lib/codexbar/CodexBarLinux_….resources/WebUI/  Bundle.module
<dest>/usr/bin/codexbar                                   symlink
<dest>/usr/share/codexbar/resources/                      icons + locales
<dest>/usr/share/applications/app.codexbar.linux.desktop
<dest>/usr/share/icons/hicolor/512x512/apps/codexbar.png
<dest>/usr/share/doc/codexbar/LICENSE
```

The constraint that binds this layout: the binary and
`CodexBarLinux_CodexBarLinuxKit.resources` must remain siblings, and
`/usr/bin/codexbar` must stay a symlink rather than a wrapper script, because
`Bundle.module` resolves through `/proc/self/exe`. A wrapper script would put
`/proc/self/exe` at the shell, and the WebUI bundle would not be found.

`stage.sh` staged 62 provider icons and 23 locales from
`Sources/CodexBar/Resources`, and refuses to produce a tree with zero of
either.

## Reproducing these measurements

The container steps use `docker` rather than `podman`, and need
`--network host`: Docker's default bridge network has no outbound route on the
development machine, so `apt-get update` inside a bridged container fails DNS
resolution before it fails anything interesting.
