// Services/RegistryServicing.swift

import Foundation

protocol RegistryServicing: Sendable {
    func list() async throws -> [RegistryEntry]
    func login(registry: String, username: String, password: String) async throws
    func logout(registry: String) async throws
}
