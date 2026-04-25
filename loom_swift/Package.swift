// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "LoomEngine",
    platforms: [
        .macOS(.v14),
        .iOS(.v17)
    ],
    products: [
        .library(name: "LoomEngine", targets: ["LoomEngine"]),
        .executable(name: "LoomApp",  targets: ["LoomApp"]),
        .executable(name: "LoomBake", targets: ["LoomBake"]),
    ],
    targets: [
        .target(
            name: "LoomEngine",
            path: "Sources/LoomEngine"
        ),
        .executableTarget(
            name: "LoomApp",
            dependencies: ["LoomEngine"],
            path: "Sources/LoomApp"
        ),
        .executableTarget(
            name: "LoomBake",
            dependencies: ["LoomEngine"],
            path: "Sources/LoomBake"
        ),
        .testTarget(
            name: "LoomEngineTests",
            dependencies: ["LoomEngine"],
            path: "Tests/LoomEngineTests"
        )
    ]
)
