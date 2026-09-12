// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "dsh-bezel",
    platforms: [.macOS(.v15)],
    targets: [
        // Connection model: Host bookmarks, the managed dsh child, and the
        // startup-line parser. Kept free of SwiftUI so it stays unit-testable.
        .target(
            name: "BezelCore",
            path: "Sources/BezelCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "dsh-bezel",
            dependencies: ["BezelCore"],
            path: "Sources/dsh-bezel",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "BezelCoreTests",
            dependencies: ["BezelCore"],
            path: "Tests/BezelCoreTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
