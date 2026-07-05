// WharfsideTests/ContainerIntegrationTests.swift

import Foundation
import Testing
@testable import Wharfside

/// Live-daemon integration tests. Skipped in CI unless `WHARFSIDE_INTEGRATION=1`.
///
/// Run locally:
/// ```bash
/// container system start
/// WHARFSIDE_INTEGRATION=1 make test
/// ```
@MainActor
struct ContainerIntegrationTests {
    private var integrationEnabled: Bool {
        ProcessInfo.processInfo.environment["WHARFSIDE_INTEGRATION"] == "1"
    }

    @Test func spikeContainerLifecycle() async throws {
        guard integrationEnabled else { return }

        let service = XPCContainerService()
        let containerID = "spike-wharfside-\(UUID().uuidString.prefix(8))"

        do {
            try await service.create(
                id: containerID,
                image: "alpine",
                command: ["/bin/sleep", "300"]
            )
            try await service.start(id: containerID)

            let stats = try await service.stats(id: containerID)
            #expect(stats.id == containerID)

            let stream = service.logStream(id: containerID, source: .stdio)
            let logTask = Task {
                for try await chunk in stream where !chunk.data.isEmpty {
                    return true
                }
                return false
            }

            try await Task.sleep(for: .seconds(1))
            logTask.cancel()
            _ = try? await logTask.value

            try await service.stop(id: containerID, timeout: 5)
            try await service.delete(id: containerID, force: false)
        } catch {
            try? await service.stop(id: containerID, timeout: 1)
            try? await service.delete(id: containerID, force: true)
            throw error
        }
    }
}
