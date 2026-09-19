// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaneSpace",
    platforms: [
        .macOS("26.0")
    ],
    products: [
        .executable(name: "PaneSpace", targets: ["PaneSpaceApp"])
    ],
    targets: [
        .executableTarget(
            name: "PaneSpaceApp",
            path: "Sources/PaneSpaceApp"
        ),
        .testTarget(
            name: "PaneSpaceTests",
            dependencies: ["PaneSpaceApp"],
            path: "Tests/PaneSpaceTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
