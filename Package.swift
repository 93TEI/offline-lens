// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OfflineLens",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "OfflineLens", targets: ["OfflineLens"])],
    targets: [
        .target(name: "OfflineLensCore"),
        .executableTarget(name: "OfflineLens", dependencies: ["OfflineLensCore"]),
        .testTarget(name: "OfflineLensCoreTests", dependencies: ["OfflineLensCore"])
    ]
)
