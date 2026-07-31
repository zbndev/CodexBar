# CodexBarLinux

Linux GUI for CodexBar. A separate SwiftPM package that depends on the
repository root by path and links the `CodexBarCore` product.

Nothing outside this directory is ever modified — the fork is synced from
upstream, so edits elsewhere would become recurring merge conflicts.

## Requirements

- Swift 6.2+
- gtk4, webkitgtk-6.0, libayatana-appindicator-glib

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

Language catalogs are read from the repository checkout during development.
Packaging copies them into the artifact in M6.
