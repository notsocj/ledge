// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Ledge",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Ledge"),
        .testTarget(name: "LedgeTests", dependencies: ["Ledge"]),
    ],
    swiftLanguageModes: [.v5]
)
