// Models/ContainerSummary.swift

import Foundation

struct ContainerSummary: Sendable, Hashable, Identifiable {
    let id: String
    let image: String
    let status: ContainerRuntimeStatus
    let startedAt: Date?
    /// Host:container port bindings, e.g. `8080:80, 3000:3000`. `—` when none.
    let portSummary: String
}
