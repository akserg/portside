// Models/ContainerSummary.swift

import Foundation

struct ContainerSummary: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let startedAt: Date?
}
