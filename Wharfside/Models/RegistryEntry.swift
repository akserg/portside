// Models/RegistryEntry.swift

import Foundation

struct RegistryEntry: Sendable, Hashable, Identifiable {
    var id: String { hostname }
    let hostname: String
    let username: String

    nonisolated init(hostname: String, username: String) {
        self.hostname = hostname
        self.username = username
    }
}
