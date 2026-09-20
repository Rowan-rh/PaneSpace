// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaneSpace",
    defaultLocalization: "en",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "PaneSpace", targets: ["PaneSpaceApp"])
    ],
    targets: [
        .executableTarget(
            name: "PaneSpaceApp",
            path: "Sources/PaneSpaceApp",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "PaneSpaceTests",
            dependencies: ["PaneSpaceApp"],
            path: "Tests/PaneSpaceTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
