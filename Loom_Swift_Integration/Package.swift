// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Loom",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Loom", targets: ["Loom"])
    ],
    dependencies: [
        .package(path: "../loom_swift")
    ],
    targets: [
        .executableTarget(
            name: "Loom",
            dependencies: [
                .product(name: "LoomEngine", package: "loom_swift")
            ],
            path: "Sources/Loom"
        )
    ]
)
