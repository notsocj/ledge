// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Kestrel",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Kestrel"),
        .testTarget(name: "KestrelTests", dependencies: ["Kestrel"]),
    ],
    swiftLanguageModes: [.v5]
)
