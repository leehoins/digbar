// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DigBar",
    platforms: [.macOS(.v14)],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "DigBar",
            dependencies: [],
            path: "Sources/DigBar",
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("CommonCrypto")
            ]
        )
    ]
)
