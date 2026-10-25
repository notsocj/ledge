// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Islet",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Islet"),
        .testTarget(name: "IsletTests", dependencies: ["Islet"]),
    ],
    swiftLanguageModes: [.v5]
)
