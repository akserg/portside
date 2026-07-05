// Models/MachineSummary.swift

import Foundation

struct MachineSummary: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let ipAddress: String?
}
