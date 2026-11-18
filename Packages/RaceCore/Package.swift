// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RaceCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RaceCore", targets: ["RaceCore"]),
    ],
    targets: [
        .target(name: "RaceCore"),
        .testTarget(name: "RaceCoreTests", dependencies: ["RaceCore"]),
    ]
)
