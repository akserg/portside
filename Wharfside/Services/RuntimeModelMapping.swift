// Services/RuntimeModelMapping.swift

import ContainerAPIClient
import ContainerResource
import ContainerizationOCI
import Foundation
import MachineAPIClient
import SystemPackage

enum RuntimeModelMapping {
    nonisolated static func containerSummary(from snapshot: ContainerSnapshot) -> ContainerSummary {
        ContainerSummary(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            startedAt: snapshot.startedDate,
            portSummary: portSummary(from: snapshot.configuration.publishedPorts)
        )
    }

    nonisolated static func portSummary(from ports: [PublishPort]) -> String {
        guard !ports.isEmpty else { return "—" }
        return ports.map { port in
            if port.hostPort == port.containerPort {
                return "\(port.hostPort)"
            }
            return "\(port.hostPort):\(port.containerPort)"
        }.joined(separator: ", ")
    }

    nonisolated static func containerDetail(from snapshot: ContainerSnapshot) -> ContainerDetail {
        let process = snapshot.configuration.initProcess
        return ContainerDetail(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            command: [process.executable] + process.arguments,
            createdAt: snapshot.configuration.creationDate,
            startedAt: snapshot.startedDate,
            exitCode: nil,
            restartCount: 0,
            ports: snapshot.configuration.publishedPorts.map(portBinding(from:)),
            mounts: snapshot.configuration.mounts.map(mount(from:)),
            environment: environmentVariables(from: process.environment),
            networks: snapshot.networks.map(networkAttachment(from:))
        )
    }

    nonisolated static func containerStats(from stats: ContainerResource.ContainerStats) -> ContainerStats {
        ContainerStats(
            id: stats.id,
            memoryUsageBytes: stats.memoryUsageBytes,
            memoryLimitBytes: stats.memoryLimitBytes,
            cpuUsageMicroseconds: stats.cpuUsageUsec,
            networkRxBytes: stats.networkRxBytes,
            networkTxBytes: stats.networkTxBytes,
            blockReadBytes: stats.blockReadBytes,
            blockWriteBytes: stats.blockWriteBytes,
            processCount: stats.numProcesses
        )
    }

    nonisolated static func imageSummary(from image: ClientImage) -> ImageSummary {
        ImageSummary(reference: image.reference, digest: image.digest)
    }

    nonisolated static func imageSummary(from resource: ImageResource) -> ImageSummary {
        let sizeBytes = resource.variants.map(\.size).max()
        return ImageSummary(
            reference: resource.displayReference,
            digest: resource.configuration.descriptor.digest,
            sizeBytes: sizeBytes,
            createdAt: resource.creationDate
        )
    }

    nonisolated static func machineSummary(from snapshot: MachineSnapshot) -> MachineSummary {
        MachineSummary(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            ipAddress: snapshot.ipAddress
        )
    }

    nonisolated static func machineDetail(from snapshot: MachineSnapshot) -> MachineDetail {
        MachineDetail(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            containerID: snapshot.containerId,
            ipAddress: snapshot.ipAddress,
            diskSizeBytes: snapshot.diskSize,
            startedAt: snapshot.startedDate,
            createdAt: snapshot.createdDate,
            initialized: snapshot.initialized
        )
    }

    nonisolated static func systemHealth(from health: ContainerAPIClient.SystemHealth) -> SystemHealth {
        SystemHealth(
            apiServerVersion: health.apiServerVersion,
            apiServerCommit: health.apiServerCommit,
            apiServerBuild: health.apiServerBuild,
            apiServerAppName: health.apiServerAppName,
            appRoot: health.appRoot,
            installRoot: health.installRoot,
            logRootPath: health.logRoot?.string
        )
    }

    nonisolated private static func portBinding(from port: PublishPort) -> ContainerPortBinding {
        ContainerPortBinding(
            hostAddress: String(describing: port.hostAddress),
            hostPort: port.hostPort,
            containerPort: port.containerPort,
            proto: port.proto.rawValue
        )
    }

    nonisolated private static func mount(from filesystem: Filesystem) -> ContainerMount {
        ContainerMount(
            source: filesystem.source,
            destination: filesystem.destination,
            type: mountTypeLabel(for: filesystem),
            readOnly: filesystem.options.readonly
        )
    }

    nonisolated private static func mountTypeLabel(for filesystem: Filesystem) -> String {
        switch filesystem.type {
        case .block(let format, _, _):
            return "block (\(format))"
        case .volume(let name, let format, _, _):
            return "volume (\(name), \(format))"
        case .virtiofs:
            return "virtiofs"
        case .tmpfs:
            return "tmpfs"
        }
    }

    nonisolated private static func environmentVariables(from raw: [String]) -> [ContainerEnvironmentVariable] {
        raw.compactMap { entry in
            guard let separator = entry.firstIndex(of: "=") else { return nil }
            let key = String(entry[..<separator])
            let valueStart = entry.index(after: separator)
            let value = String(entry[valueStart...])
            guard !key.isEmpty else { return nil }
            return ContainerEnvironmentVariable(key: key, value: value)
        }
        .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    nonisolated private static func networkAttachment(from attachment: Attachment) -> ContainerNetworkAttachment {
        ContainerNetworkAttachment(
            network: attachment.network,
            hostname: attachment.hostname,
            ipv4Address: String(describing: attachment.ipv4Address),
            ipv4Gateway: String(describing: attachment.ipv4Gateway),
            ipv6Address: attachment.ipv6Address.map { String(describing: $0) }
        )
    }

    nonisolated private static func runtimeStatus(_ status: RuntimeStatus) -> ContainerRuntimeStatus {
        ContainerRuntimeStatus(rawValue: status.rawValue) ?? .unknown
    }
}
