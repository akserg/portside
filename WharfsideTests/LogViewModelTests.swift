// WharfsideTests/LogViewModelTests.swift

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
struct LogViewModelTests {
    @Test func stopCancelsActiveStream() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(LogChunk(source: .stdio, data: Data("line\n".utf8)))
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .running)
        #expect(await TestPolling.waitUntil { viewModel.isStreamActive })

        viewModel.stop()
        #expect(await TestPolling.waitUntil { !viewModel.isStreamActive })
    }

    @Test func searchFiltersLiveAppendedLines() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("INFO tick\n".utf8)))
                continuation.yield(LogChunk(source: .stdio, data: Data("ERROR boom\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .running)
        #expect(await TestPolling.waitUntil {
            viewModel.displayRows.contains { row in
                if case .line(let line) = row { return line.text == "ERROR boom" }
                return false
            }
        })

        viewModel.searchText = "boom"
        let rows = viewModel.displayRows.compactMap { row -> String? in
            guard case .line(let line) = row else { return nil }
            return line.text
        }
        #expect(rows == ["ERROR boom"])
        #expect(viewModel.matchCount == 1)
    }

    @Test func followTailPinUnpinStateMachine() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(LogChunk(source: .stdio, data: Data("first\n".utf8)))
                    try? await Task.sleep(for: .milliseconds(80))
                    continuation.yield(LogChunk(source: .stdio, data: Data("second\n".utf8)))
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .running)
        #expect(await TestPolling.waitUntil {
            viewModel.displayRows.contains { row in
                if case .line(let line) = row { return line.text == "first" }
                return false
            }
        })

        #expect(viewModel.isTailPinned)
        #expect(!viewModel.showJumpToLatest)

        viewModel.userScrolledUp()
        #expect(!viewModel.isTailPinned)

        #expect(await TestPolling.waitUntil { viewModel.showJumpToLatest })

        viewModel.jumpToLatest()
        #expect(viewModel.isTailPinned)
        #expect(!viewModel.showJumpToLatest)
    }

    @Test func stoppedContainerShowsEndCapAfterSnapshot() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("history\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { viewModel.isStreamFinished })

        #expect(viewModel.displayRows.contains(.stoppedCap))
        #expect(viewModel.displayRows.compactMap { row -> String? in
            guard case .line(let line) = row else { return nil }
            return line.text
        } == ["history"])
    }

    @Test func reattachesWhenContainerRestarts() async {
        let service = MockContainerService()
        service.logStreamFactory = { [service] _, _ in
            let generation = service.logStreamCallCount
            return AsyncThrowingStream { continuation in
                continuation.yield(
                    LogChunk(source: .stdio, data: Data("gen-\(generation)\n".utf8))
                )
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 1 })

        viewModel.updateContainerStatus(.running)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount >= 2 })

        let texts = viewModel.displayRows.compactMap { row -> String? in
            guard case .line(let line) = row else { return nil }
            return line.text
        }
        #expect(texts.contains("gen-2"))
    }

    @Test func recentEntriesAccessorReturnsParsedBufferWindow() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("ERROR: fail\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { !viewModel.recentEntries(window: .seconds(60)).isEmpty })

        let entries = viewModel.recentEntries(window: .seconds(60))
        #expect(entries.count == 1)
        #expect(entries.first?.level == .error)
    }

    @Test func clearDisplayEmptiesBufferButKeepsStream() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                let task = Task {
                    continuation.yield(LogChunk(source: .stdio, data: Data("one\n".utf8)))
                    while !Task.isCancelled {
                        try? await Task.sleep(for: .milliseconds(50))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .running)
        #expect(await TestPolling.waitUntil { !viewModel.displayRows.isEmpty })

        viewModel.clearDisplay()
        #expect(viewModel.displayRows.isEmpty)
        #expect(viewModel.isStreamActive)
    }

    @Test func filterSwitchesDoNotDuplicateBufferOrDiagnosisWindow() async {
        // The app printed the ERROR line once; `logStream` re-delivers that whole-file
        // snapshot on every restart. Toggling stdio → boot → stdio must not accrete copies
        // into the display buffer or (worse) into the diagnosis window fed to the digest.
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("ERROR boom\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 1 })

        viewModel.sourceFilter = .boot
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 2 })
        viewModel.sourceFilter = .stdio
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 3 })
        #expect(await TestPolling.waitUntil {
            viewModel.isStreamFinished
                && viewModel.displayRows.compactMap { row -> String? in
                    guard case .line(let line) = row else { return nil }
                    return line.text
                } == ["ERROR boom"]
        })

        // Display layer: buffer cleared on each toggle — no visible triples, no Copy triples.
        let lineTexts = viewModel.displayRows.compactMap { row -> String? in
            guard case .line(let line) = row else { return nil }
            return line.text
        }
        #expect(lineTexts == ["ERROR boom"])

        // Integrity layer: the diagnosis window contains the entry exactly once.
        let windowEntries = viewModel.recentEntries(window: .seconds(3600))
        #expect(windowEntries.filter { $0.raw == "ERROR boom" }.count == 1)
    }

    @Test func sourceFilterChangeRestartsStream() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, source in
            AsyncThrowingStream { continuation in
                let label = source?.rawValue ?? "both"
                continuation.yield(LogChunk(source: .stdio, data: Data("\(label)\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .running)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 1 })
        let initialCalls = service.logStreamCallCount

        viewModel.sourceFilter = .boot
        #expect(await TestPolling.waitUntil { service.logStreamCallCount > initialCalls })

        #expect(service.lastLogStreamSource == .boot)
    }

    /// Logs → Overview → Logs (`onDisappear`→`stop()` then `onAppear`→`start()`) re-attaches
    /// the stream and re-delivers a whole-file snapshot. Without a clear at reattach, the
    /// display buffer accretes one copy per round trip (diagnosis `recentEntries` dedup
    /// hides this from digests — display-only defect, same accumulation family as Bug A).
    @Test func reattachDoesNotDuplicateDisplayBufferOrDiagnosisWindow() async {
        let service = MockContainerService()
        service.logStreamFactory = { _, _ in
            AsyncThrowingStream { continuation in
                continuation.yield(LogChunk(source: .stdio, data: Data("ERROR boom\n".utf8)))
                continuation.finish()
            }
        }

        let viewModel = LogViewModel(containerID: "app", service: service)
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 1 })
        #expect(await TestPolling.waitUntil { viewModel.isStreamFinished })

        // Two Logs→Overview→Logs round trips.
        viewModel.stop()
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 2 })
        #expect(await TestPolling.waitUntil { viewModel.isStreamFinished })
        viewModel.stop()
        viewModel.start(containerStatus: .stopped)
        #expect(await TestPolling.waitUntil { service.logStreamCallCount == 3 })
        #expect(await TestPolling.waitUntil { viewModel.isStreamFinished })

        let lineTexts = viewModel.displayRows.compactMap { row -> String? in
            guard case .line(let line) = row else { return nil }
            return line.text
        }
        #expect(lineTexts == ["ERROR boom"])

        let windowEntries = viewModel.recentEntries(window: .seconds(3600))
        #expect(windowEntries.filter { $0.raw == "ERROR boom" }.count == 1)
    }
}
