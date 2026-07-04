import ContainerAPIClient
import ContainerPersistence
import ContainerResource
import Containerization
import ContainerizationError
import ContainerizationOCI
import Foundation
import SystemPackage

enum ProbeError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}

func formatError(_ error: Error) -> String {
    if let err = error as? ContainerizationError {
        var parts = ["ContainerizationError(code: \(err.code), message: \(err.message)"]
        if let cause = err.cause {
            parts.append("cause: \(cause)")
        }
        return parts.joined(separator: ", ") + ")"
    }
    if let err = error as? VolumeError {
        return "VolumeError: \(err)"
    }
    let ns = error as NSError
    return "NSError(domain: \(ns.domain), code: \(ns.code), description: \(ns.localizedDescription), userInfo: \(ns.userInfo))"
}

func printResult(_ label: String, _ value: some CustomStringConvertible) {
    print("OK \(label): \(value)")
}

func printFailure(_ label: String, _ error: Error) {
    print("FAIL \(label): \(formatError(error))")
}

func loadSystemConfig() async throws -> ContainerSystemConfig {
    let health = try await ClientHealthCheck.ping(timeout: .seconds(10))
    let appRoot = FilePath(health.appRoot.path(percentEncoded: false))
    let installRoot = FilePath(health.installRoot.path(percentEncoded: false))
    return try await ConfigurationLoader.load(
        configurationFiles: [
            ConfigurationLoader.configurationFile(in: appRoot, of: .appRoot),
            ConfigurationLoader.configurationFile(in: installRoot, of: .installRoot),
        ]
    )
}

func prepareImage(reference: String, systemConfig: ContainerSystemConfig) async throws -> ClientImage {
    let image = try await ClientImage.get(reference: reference, containerSystemConfig: systemConfig)
    let platform = Platform.current
    _ = try await image.getCreateSnapshot(platform: platform)
    return image
}

func prepareInitImage(systemConfig: ContainerSystemConfig) async throws {
    let initRef = systemConfig.vminit.image
    let initImage = try await ClientImage.fetch(
        reference: initRef,
        platform: .current,
        containerSystemConfig: systemConfig
    )
    _ = try await initImage.getCreateSnapshot(platform: .current)
}

func makeContainerConfig(
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

func createAndStartContainer(
    id: String,
    imageRef: String,
    command: [String] = ["/bin/sleep", "300"]
) async throws -> String {
    let systemConfig = try await loadSystemConfig()
    _ = try await prepareInitImage(systemConfig: systemConfig)
    let image = try await prepareImage(reference: imageRef, systemConfig: systemConfig)
    let (config, kernel) = try await makeContainerConfig(
        id: id,
        image: image,
        command: command,
        systemConfig: systemConfig
    )

    let client = ContainerClient()
    try await client.create(configuration: config, options: .default, kernel: kernel)

    let nullOut = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
    let process = try await client.bootstrap(id: id, stdio: [nil, nullOut, nullOut])
    try await process.start()
    return id
}

func deleteContainerIfExists(_ id: String) async {
    let client = ContainerClient()
    do {
        try await client.delete(id: id, force: true)
        print("CLEANUP deleted container \(id)")
    } catch {
        print("CLEANUP skip container \(id): \(formatError(error))")
    }
}

func deleteVolumeIfExists(_ name: String) async {
    do {
        try await ClientVolume.delete(name: name)
        print("CLEANUP deleted volume \(name)")
    } catch {
        print("CLEANUP skip volume \(name): \(formatError(error))")
    }
}

func tagImageIfExists(_ source: String, _ target: String) async {
    do {
        let systemConfig = try await loadSystemConfig()
        let image = try await ClientImage.get(reference: source, containerSystemConfig: systemConfig)
        _ = try await image.tag(new: target)
        print("CLEANUP tagged \(source) -> \(target)")
    } catch {
        print("CLEANUP skip tag \(source): \(formatError(error))")
    }
}
