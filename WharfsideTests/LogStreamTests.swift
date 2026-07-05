// WharfsideTests/LogStreamTests.swift

import Testing
@testable import Wharfside

@MainActor
struct LogStreamTests {
    @Test func cancellationFinishesStream() async throws {
        let service = MockContainerService()
        let stream = service.logStream(id: "mock", source: nil)

        var received = 0
        let consumeTask = Task {
            for try await _ in stream {
                received += 1
            }
        }

        try await Task.sleep(for: .milliseconds(50))
        consumeTask.cancel()

        _ = await consumeTask.result
        #expect(received >= 1)
    }
}
