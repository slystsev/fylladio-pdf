// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Folio",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "FolioCore", path: "Sources/FolioCore"),
        .executableTarget(name: "Folio", dependencies: ["FolioCore"], path: "Sources/Folio"),
        .executableTarget(name: "FolioCheck", dependencies: ["FolioCore"], path: "Sources/FolioCheck"),
    ]
)
