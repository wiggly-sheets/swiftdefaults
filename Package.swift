// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftDefaults",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "SwiftDefaults",
            path: "SwiftDefaults",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "SwiftDefaultsTests", dependencies: ["SwiftDefaults"])
    ]
)
