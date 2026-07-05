// Models/ContainerRuntimeStatus.swift

import Foundation

/// Runtime status mirrored from apple/container 1.0 (`RuntimeStatus` has no `paused`).
enum ContainerRuntimeStatus: String, Sendable, Codable, CaseIterable {
    case unknown
    case stopped
    case running
    case stopping
}
