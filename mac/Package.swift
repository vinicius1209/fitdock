// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "FitDock",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FitDock", targets: ["FitDock"])
    ],
    targets: [
        .executableTarget(name: "FitDock")
    ],
    swiftLanguageModes: [.v5]
)
