// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodexBarLinux",
    products: [
        .executable(name: "CodexBarLinux", targets: ["CodexBarLinux"]),
    ],
    dependencies: [
        .package(path: ".."),
    ],
    targets: [
        .systemLibrary(
            name: "CGtk4",
            path: "Sources/CGtk4",
            pkgConfig: "gtk4",
            providers: [.apt(["libgtk-4-dev"])]),
        .systemLibrary(
            name: "CWebKitGTK",
            path: "Sources/CWebKitGTK",
            pkgConfig: "webkitgtk-6.0",
            providers: [.apt(["libwebkitgtk-6.0-dev"])]),
        .systemLibrary(
            name: "CAyatanaAppIndicator",
            path: "Sources/CAyatanaAppIndicator",
            pkgConfig: "ayatana-appindicator-glib",
            providers: [.apt(["libayatana-appindicator3-dev"])]),
        .target(
            name: "CodexBarLinuxKit",
            dependencies: [
                "CGtk4",
                "CWebKitGTK",
                "CAyatanaAppIndicator",
                .product(name: "CodexBarCore", package: "CodexBar"),
            ],
            path: "Sources/CodexBarLinuxKit",
            resources: [.copy("../WebUI")],
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .executableTarget(
            name: "CodexBarLinux",
            dependencies: ["CodexBarLinuxKit"],
            path: "Sources/CodexBarLinux",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
        .testTarget(
            name: "CodexBarLinuxKitTests",
            dependencies: ["CodexBarLinuxKit"],
            path: "Tests/CodexBarLinuxKitTests",
            swiftSettings: [.enableUpcomingFeature("StrictConcurrency")]),
    ])
