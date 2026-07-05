// Models/SecretReference.swift

import Foundation

/// Opaque handle for registry credentials stored in the Keychain (CLI login path).
struct SecretReference: Sendable, Hashable {
    let registryHost: String
    let keychainDomain: String
}
