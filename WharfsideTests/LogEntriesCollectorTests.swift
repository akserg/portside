// WharfsideTests/LogEntriesCollectorTests.swift

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
struct LogEntriesCollectorTests {
    @Test func collectReturnsAfterTimeoutWhenStreamNeverFinishes() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("ERROR: disk full\n".utf8)))
                // Mimic XPC logStream: poll loop never calls finish().
            }
        }

        let start = ContinuousClock.now
        let entries = await LogEntriesCollector.collect(
            from: service,
            containerID: "crashy",
            maxDuration: .milliseconds(100)
        )
        let elapsed = start.duration(to: .now)

        #expect(!entries.isEmpty)
        #expect(elapsed < .seconds(1))
    }
}
