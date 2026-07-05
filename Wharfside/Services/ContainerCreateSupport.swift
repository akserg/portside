// Services/ContainerCreateSupport.swift

import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import SystemPackage

enum ContainerCreateSupport {
    static func loadSystemConfig() async throws -> ContainerSystemConfig {
        let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
        let appRoot = FilePath(health.appRoot.path(percentEncoded: false))
        let installRoot = FilePath(health.installRoot.path(percentEncoded: false))
        return try await ConfigurationLoader.load(
            configurationFiles: [
                ConfigurationLoader.configurationFile(in: appRoot, of: .appRoot),
                ConfigurationLoader.configurationFile(in: installRoot, of: .installRoot)
            ]
        )
    }

    static func prepareInitImage(systemConfig: ContainerSystemConfig) async throws {
        let initRef = systemConfig.vminit.image
        let initImage = try await ClientImage.fetch(
            reference: initRef,
            platform: .current,
            containerSystemConfig: systemConfig
        )
        _ = try await initImage.getCreateSnapshot(platform: .current)
    }

    static func prepareImage(reference: String, systemConfig: ContainerSystemConfig) async throws -> ClientImage {
        let image = try await ClientImage.get(reference: reference, containerSystemConfig: systemConfig)
        _ = try await image.getCreateSnapshot(platform: .current)
        return image
    }

    static func makeConfiguration(
        id: String,
        image: ClientImage,
        command: [String],
        systemConfig: ContainerSystemConfig
    ) async throws -> (ContainerConfiguration, Kernel) {
        let platform = Platform.current
        let ociImage = try await image.config(for: platform)
        let imageConfig = ociImage.config
        let executable = command.first ?? "/bin/sh"
        let args = Array(command.dropFirst())
        let process = ProcessConfiguration(
            executable: executable,
            arguments: args,
            environment: imageConfig?.env ?? [],
            workingDirectory: imageConfig?.workingDir ?? "/",
            terminal: false,
            user: .raw(userString: imageConfig?.user ?? "root")
        )

        var config = ContainerConfiguration(id: id, image: image.description, process: process)
        config.platform = platform
        config.resources.cpus = systemConfig.container.cpus
        config.resources.memoryInBytes = systemConfig.container.memory.toUInt64(unit: .bytes)

        let kernel = try await ClientKernel.getDefaultKernel(for: .current)
        return (config, kernel)
    }
}
