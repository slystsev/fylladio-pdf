// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fylladio",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FylladioCore", path: "Sources/FylladioCore"),
        .executableTarget(name: "Fylladio", dependencies: ["FylladioCore"], path: "Sources/Fylladio"),
        .executableTarget(name: "FylladioCheck", dependencies: ["FylladioCore"], path: "Sources/FylladioCheck"),
    ]
)
