// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WharfsideAnalysis",
    platforms: [.macOS("26")],
    products: [
        .library(name: "WharfsideAnalysis", targets: ["WharfsideAnalysis"]),
    ],
    targets: [
        .target(name: "WharfsideAnalysis"),
        .testTarget(
            name: "WharfsideAnalysisTests",
            dependencies: ["WharfsideAnalysis"]
        ),
    ]
)
