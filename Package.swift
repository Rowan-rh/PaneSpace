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
    dependencies: [
        // The appcast format and channel semantics evolve between minor versions, and the
        // update path of an installed app is not something to change without review, so
        // the version is pinned exactly rather than by range. See docs/adr/0011.
        .package(url: "https://github.com/sparkle-project/Sparkle.git", exact: "2.10.0")
    ],
    targets: [
        .executableTarget(
            name: "PaneSpaceApp",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
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
