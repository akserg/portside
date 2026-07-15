// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WharfsideAnalysis",
    platforms: [.macOS("26")],
    products: [
        .library(name: "WharfsideAnalysis", targets: ["WharfsideAnalysis"]),
        .executable(name: "digest-preview", targets: ["DigestPreview"]),
    ],
    dependencies: [
        .package(path: "../RulebookCore"),
        .package(url: "https://github.com/apple/swift-crypto", from: "3.0.0"),
    ],
    targets: [
        .target(
            name: "WharfsideAnalysis",
            dependencies: [
                .product(name: "RulebookCore", package: "RulebookCore"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
        .executableTarget(
            name: "DigestPreview",
            dependencies: ["WharfsideAnalysis"]
        ),
        .testTarget(
            name: "WharfsideAnalysisTests",
            dependencies: [
                "WharfsideAnalysis",
                .product(name: "RulebookCore", package: "RulebookCore"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)
