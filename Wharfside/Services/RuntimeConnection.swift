// Services/RuntimeConnection.swift

import ContainerAPIClient
import Foundation
import MachineAPIClient

/// Holds reusable XPC clients and recreates them after `.interrupted` errors.
///
/// `ContainerClient` is a cheap `Sendable` struct wrapping a reusable `XPCClient`; we cache one
/// instance per service actor and replace it when the connection is dropped (capability map §5).
actor RuntimeConnection {
    private var containerClient = ContainerClient()
    private var machineClient = MachineClient()

    func withContainerClient<T>(
        retryOnInterrupt: Bool,
        _ operation: (ContainerClient) async throws -> T
    ) async throws -> T {
        try await perform(retryOnInterrupt: retryOnInterrupt, recreate: recreateContainerClient) {
            try await operation(containerClient)
        }
    }

    func withMachineClient<T>(
        retryOnInterrupt: Bool,
        _ operation: (MachineClient) async throws -> T
    ) async throws -> T {
        try await perform(retryOnInterrupt: retryOnInterrupt, recreate: recreateMachineClient) {
            try await operation(machineClient)
        }
    }

    private func recreateContainerClient() {
        containerClient = ContainerClient()
    }

    private func recreateMachineClient() {
        machineClient = MachineClient()
    }

    private func perform<T>(
        retryOnInterrupt: Bool,
        recreate: () -> Void,
        _ operation: () async throws -> T
    ) async throws -> T {
        let maxAttempts = retryOnInterrupt ? 2 : 1
        var lastError: Error?

        for attempt in 1...maxAttempts {
            do {
                return try await operation()
            } catch {
                lastError = error
                let shouldRetry = retryOnInterrupt
                    && attempt < maxAttempts
                    && ErrorMapper.isInterrupted(error)
                if shouldRetry {
                    recreate()
                    continue
                }
                throw ErrorMapper.map(error)
            }
        }

        throw ErrorMapper.map(lastError ?? WharfsideError.apiError("Unknown error"))
    }
}

enum ConnectionRetryPolicy {
    nonisolated static func shouldRetry(
        retryOnInterrupt: Bool,
        error: Error,
        attempt: Int,
        maxAttempts: Int
    ) -> Bool {
        retryOnInterrupt && attempt < maxAttempts && ErrorMapper.isInterrupted(error)
    }
}
