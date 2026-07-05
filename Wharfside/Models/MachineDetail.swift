// Models/MachineDetail.swift

import Foundation

struct MachineDetail: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let containerID: String?
    let ipAddress: String?
    let diskSizeBytes: UInt64?
    let startedAt: Date?
    let createdAt: Date?
    let initialized: Bool
}
