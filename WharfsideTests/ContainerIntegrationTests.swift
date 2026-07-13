// WharfsideTests/ContainerIntegrationTests.swift

import Foundation
import Testing
import WharfsideAnalysis
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

            let exitStatus = await service.exitStatus(id: containerID)
            if case .unavailable(.runtimeGone) = exitStatus {
                // Expected after stop completes — init exit is recovered from boot log at diagnosis time (B1.1).
            } else if case .known(let code, source: .runtime) = exitStatus {
                #expect(code == 137 || code == 143 || code == 0,
                        "transient runtime exit during stop, got \(code)")
            } else {
                Issue.record("expected runtimeGone after stop (or transient known runtime), got \(exitStatus)")
            }

            try await service.delete(id: containerID, force: false)
        } catch {
            try? await service.stop(id: containerID, timeout: 1)
            try? await service.delete(id: containerID, force: true)
            throw error
        }
    }
}
