// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "LyricsPiPCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "LyricsPiPCore", targets: ["LyricsPiPCore"])
    ],
    targets: [
        .target(name: "LyricsPiPCore"),
        .testTarget(name: "LyricsPiPCoreTests", dependencies: ["LyricsPiPCore"])
    ]
)
