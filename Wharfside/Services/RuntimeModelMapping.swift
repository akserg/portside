// Services/RuntimeModelMapping.swift

import ContainerAPIClient
import ContainerResource
import Foundation
import MachineAPIClient
import SystemPackage

enum RuntimeModelMapping {
    nonisolated static func containerSummary(from snapshot: ContainerSnapshot) -> ContainerSummary {
        ContainerSummary(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            startedAt: snapshot.startedDate
        )
    }

    nonisolated static func containerDetail(from snapshot: ContainerSnapshot) -> ContainerDetail {
        let process = snapshot.configuration.initProcess
        return ContainerDetail(
            id: snapshot.id,
            image: snapshot.configuration.image.reference,
            status: runtimeStatus(snapshot.status),
            command: [process.executable] + process.arguments,
            environmentCount: process.environment.count,
            mountCount: snapshot.configuration.mounts.count,
            publishedPortCount: snapshot.configuration.publishedPorts.count,
            networkCount: snapshot.networks.count,
            startedAt: snapshot.startedDate
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

    nonisolated private static func runtimeStatus(_ status: RuntimeStatus) -> ContainerRuntimeStatus {
        ContainerRuntimeStatus(rawValue: status.rawValue) ?? .unknown
    }
}
