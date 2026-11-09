// swift-tools-version:5.8
import PackageDescription

let package = Package(
    name: "mfish",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MFish", targets: ["MFish"])],
    targets: [
        .target(name: "FishCore"),
        .executableTarget(name: "MFish", dependencies: ["FishCore"]),
        .testTarget(name: "FishCoreTests", dependencies: ["FishCore"]),
    ]
)