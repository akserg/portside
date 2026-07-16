// WharfsideTests/LogEntriesCollectorTests.swift

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
struct LogEntriesCollectorTests {
    @Test func collectReturnsAfterTimeoutWhenStreamNeverFinishes() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, source in
            AsyncThrowingStream { continuation in
                if source == .stdio {
                    continuation.yield(LogChunk(source: .stdio, data: Data("ERROR: disk full\n".utf8)))
                }
                // Never finish — mimics live XPC log handles that poll indefinitely.
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
        #expect(entries.contains { $0.source == .stdio })
        // Two phases (stdio + boot), each capped at maxDuration. Under CI load, cancelling
        // never-finishing streams can push past 1 s — stay under the production 2 s phase cap.
        #expect(elapsed < .seconds(2))
    }

    @Test func collectFallsBackToBootWhenStdioEmpty() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, source in
            AsyncThrowingStream { continuation in
                if source == .stdio {
                    continuation.finish()
                } else if source == .boot {
                    continuation.yield(
                        LogChunk(source: .boot, data: Data("ERROR: rootfs mount failed\n".utf8))
                    )
                }
            }
        }

        let entries = await LogEntriesCollector.collect(
            from: service,
            containerID: "init-fail",
            maxDuration: .milliseconds(100)
        )

        #expect(entries.count == 1)
        #expect(entries.first?.source == .boot)
        #expect(entries.first?.raw.contains("rootfs mount failed") == true)
    }

    @Test func collectIncludesBootAlongsideStdio() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, source in
            AsyncThrowingStream { continuation in
                if source == .stdio {
                    continuation.yield(
                        LogChunk(source: .stdio, data: Data("ERROR: No space left on device\n".utf8))
                    )
                } else if source == .boot {
                    continuation.yield(
                        LogChunk(
                            source: .boot,
                            data: Data("info vminitd: id: crashy, status: 1 managed process exit\n".utf8)
                        )
                    )
                }
                continuation.finish()
            }
        }

        let entries = await LogEntriesCollector.collect(
            from: service,
            containerID: "crashy",
            maxDuration: .milliseconds(100)
        )

        #expect(entries.contains { $0.source == .stdio })
        #expect(entries.contains { $0.source == .boot })
        #expect(entries.contains { $0.raw.contains("No space left on device") })
        #expect(entries.contains { $0.raw.contains("status: 1 managed process exit") })
    }

    @Test func assembleEvidenceUsesBufferedStdioAndColdBoot() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, source in
            AsyncThrowingStream { continuation in
                if source == .boot {
                    continuation.yield(
                        LogChunk(
                            source: .boot,
                            data: Data("info vminitd: id: app, status: 1 managed process exit\n".utf8)
                        )
                    )
                }
                continuation.finish()
            }
        }

        let buffered = [
            LogEntry(
                timestamp: nil,
                level: .error,
                message: "boom",
                raw: "ERROR boom",
                source: .stdio
            )
        ]
        let entries = await LogEntriesCollector.assembleEvidence(
            from: service,
            containerID: "app",
            buffered: buffered,
            maxDuration: .milliseconds(100)
        )

        #expect(service.logStreamCallCount == 1)
        #expect(service.lastLogStreamSource == .boot)
        #expect(entries.filter { $0.source == .stdio }.map(\.raw) == ["ERROR boom"])
        #expect(entries.contains { $0.source == .boot && $0.raw.contains("status: 1") })
    }
}
