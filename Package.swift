// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AriaRuntime",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "AriaRuntimeShared", targets: ["AriaRuntimeShared"]),
        .library(name: "AriaRuntimeMacOS", targets: ["AriaRuntimeMacOS"]),
        .executable(name: "aria-runtime-daemon", targets: ["AriaRuntimeDaemon"]),
        .executable(name: "aria", targets: ["AriaRuntimeCLI"]),
        .executable(name: "AriaRuntimeApp", targets: ["AriaRuntimeApp"]),
    ],
    targets: [
        .target(
            name: "AriaRuntimeShared"
        ),
        .target(
            name: "AriaRuntimeMacOS",
            dependencies: ["AriaRuntimeShared"]
        ),
        .executableTarget(
            name: "AriaRuntimeDaemon",
            dependencies: ["AriaRuntimeShared", "AriaRuntimeMacOS"]
        ),
        .executableTarget(
            name: "AriaRuntimeCLI",
            dependencies: ["AriaRuntimeShared", "AriaRuntimeMacOS"]
        ),
        .executableTarget(
            name: "AriaRuntimeApp",
            dependencies: ["AriaRuntimeShared", "AriaRuntimeMacOS"]
        ),
        .testTarget(
            name: "AriaRuntimeSharedTests",
            dependencies: ["AriaRuntimeShared"]
        ),
    ]
)
