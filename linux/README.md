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
