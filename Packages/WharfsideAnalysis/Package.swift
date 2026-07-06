// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WharfsideAnalysis",
    platforms: [.macOS("26")],
    products: [
        .library(name: "WharfsideAnalysis", targets: ["WharfsideAnalysis"]),
        .executable(name: "digest-preview", targets: ["DigestPreview"]),
    ],
    targets: [
        .target(name: "WharfsideAnalysis"),
        .executableTarget(
            name: "DigestPreview",
            dependencies: ["WharfsideAnalysis"]
        ),
        .testTarget(
            name: "WharfsideAnalysisTests",
            dependencies: ["WharfsideAnalysis"]
        ),
    ]
)
