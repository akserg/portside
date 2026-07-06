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
        try? await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.isStreamActive)

        viewModel.stop()
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!viewModel.isStreamActive)
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
        try? await Task.sleep(for: .milliseconds(80))

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
        try? await Task.sleep(for: .milliseconds(40))

        #expect(viewModel.isTailPinned)
        #expect(!viewModel.showJumpToLatest)

        viewModel.userScrolledUp()
        #expect(!viewModel.isTailPinned)

        try? await Task.sleep(for: .milliseconds(80))
        #expect(viewModel.showJumpToLatest)

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
        try? await Task.sleep(for: .milliseconds(80))

        #expect(viewModel.isStreamFinished)
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
        try? await Task.sleep(for: .milliseconds(80))
        #expect(service.logStreamCallCount == 1)

        viewModel.updateContainerStatus(.running)
        try? await Task.sleep(for: .milliseconds(120))
        #expect(service.logStreamCallCount >= 2)

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
        try? await Task.sleep(for: .milliseconds(80))

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
        try? await Task.sleep(for: .milliseconds(80))
        #expect(!viewModel.displayRows.isEmpty)

        viewModel.clearDisplay()
        #expect(viewModel.displayRows.isEmpty)
        #expect(viewModel.isStreamActive)
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
        try? await Task.sleep(for: .milliseconds(80))
        let initialCalls = service.logStreamCallCount

        viewModel.sourceFilter = .boot
        try? await Task.sleep(for: .milliseconds(80))

        #expect(service.logStreamCallCount > initialCalls)
        #expect(service.lastLogStreamSource == .boot)
    }
}
