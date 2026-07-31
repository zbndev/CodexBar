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
        .target(
            name: "CodexBarLinuxKit",
            dependencies: [
                "CGtk4",
                .product(name: "CodexBarCore", package: "CodexBar"),
            ],
            path: "Sources/CodexBarLinuxKit",
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
