// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "xpc-probe",
    platforms: [.macOS("26")],
    dependencies: [
        .package(url: "https://github.com/apple/container.git", exact: "1.0.0"),
        .package(url: "https://github.com/apple/containerization.git", exact: "0.33.3"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .executableTarget(
            name: "xpc-probe",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ContainerAPIClient", package: "container"),
                .product(name: "MachineAPIClient", package: "container"),
                .product(name: "ContainerPersistence", package: "container"),
                .product(name: "ContainerResource", package: "container"),
                .product(name: "ContainerXPC", package: "container"),
                .product(name: "ContainerizationOS", package: "containerization"),
            ]
        ),
    ]
)
