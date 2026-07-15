// Models/ContainerDetail.swift

import Foundation
import WharfsideAnalysis

struct ContainerDetail: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let command: [String]
    let createdAt: Date
    let startedAt: Date?
    let exitStatus: ExitStatus
    let restartCount: Int
    let ports: [ContainerPortBinding]
    let mounts: [ContainerMount]
    let environment: [ContainerEnvironmentVariable]
    let networks: [ContainerNetworkAttachment]
}
