// ViewModels/LogViewModel.swift

import Foundation
import Observation
import WharfsideAnalysis

enum LogDisplayRow: Identifiable, Equatable, Sendable {
    case line(BufferedLogLine)
    case stoppedCap

    var id: String {
        switch self {
        case .line(let line):
            "line-\(line.id)"
        case .stoppedCap:
            "stopped-cap"
        }
    }
}

@MainActor
@Observable
final class LogViewModel {
    let containerID: String

    private(set) var bufferRevision = 0
    private(set) var isStreamActive = false
    private(set) var isStreamFinished = false
    private(set) var hasUnseenLinesWhileUnpinned = false

    var sourceFilter: LogViewSourceFilter = .stdio {
        didSet {
            guard oldValue != sourceFilter else { return }
            restartStream()
        }
    }

    var searchText = ""
    var isTailPinned = true
    var isPaused = false
    var isLineWrapEnabled = false

    private var buffer = LogRingBuffer()
    private var containerIsRunning = false
    private var streamTask: Task<Void, Never>?
    /// Bumped on every `restartStream` so a cancelled consumer cannot append or flip
    /// `isStreamFinished` after a newer attach has taken over (filter toggles / reattach).
    private var streamGeneration: UInt64 = 0
    private let service: any ContainerServicing

    init(containerID: String, service: any ContainerServicing) {
        self.containerID = containerID
        self.service = service
    }

    var displayRows: [LogDisplayRow] {
        _ = bufferRevision
        let filtered = buffer.filtered(search: searchText, sources: sourceFilter)
        var rows = filtered.lines.map(LogDisplayRow.line)
        if isStreamFinished && !containerIsRunning {
            rows.append(.stoppedCap)
        }
        return rows
    }

    var matchCount: Int {
        _ = bufferRevision
        return buffer.filtered(search: searchText, sources: sourceFilter).matchCount
    }

    var showJumpToLatest: Bool {
        !isTailPinned && hasUnseenLinesWhileUnpinned
    }

    var showsSearchMatchCount: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func start(containerStatus: ContainerRuntimeStatus) {
        containerIsRunning = containerStatus == .running || containerStatus == .stopping
        restartStream()
    }

    func stop() {
        streamTask?.cancel()
        streamTask = nil
        isStreamActive = false
    }

    func updateContainerStatus(_ status: ContainerRuntimeStatus) {
        let wasRunning = containerIsRunning
        containerIsRunning = status == .running || status == .stopping
        if !wasRunning && containerIsRunning && isStreamFinished {
            restartStream()
        }
        if !containerIsRunning {
            bufferRevision += 1
        }
    }

    func userScrolledUp() {
        guard isTailPinned else { return }
        isTailPinned = false
    }

    func jumpToLatest() {
        isTailPinned = true
        hasUnseenLinesWhileUnpinned = false
    }

    func clearDisplay() {
        buffer.clear()
        bufferRevision += 1
    }

    func togglePause() {
        isPaused.toggle()
    }

    func visibleLinesText() -> String {
        displayRows.compactMap { row in
            guard case .line(let line) = row else { return nil }
            return line.text
        }
        .joined(separator: "\n")
    }

#if DEBUG
    /// Seeds the ring buffer from fixture chunks without starting a live stream.
    /// Used by launch-asset snapshot / pose modes (`scrollable: false` LogView).
    func seedFixtureChunks(_ chunks: [LogChunk], containerIsRunning: Bool) {
        stop()
        buffer.clear()
        for chunk in chunks {
            buffer.append(chunk: chunk)
        }
        self.containerIsRunning = containerIsRunning
        isStreamFinished = true
        isStreamActive = false
        isTailPinned = true
        hasUnseenLinesWhileUnpinned = false
        bufferRevision += 1
    }
#endif

    /// Returns parsed log entries from the in-memory buffer within the given time window.
    ///
    /// Issue 1.6 (`LogDiagnosisService`) should call this with the visible tail window
    /// (e.g. `.seconds(300)`) to feed Layer 1 digestion without re-reading container logs.
    func recentEntries(window: Duration) -> [LogEntry] {
        _ = bufferRevision
        return buffer.recentEntries(within: window)
    }

    private func restartStream() {
        streamTask?.cancel()
        streamTask = nil
        isStreamFinished = false
        isStreamActive = false

        // Every (re)attach re-delivers a whole-file snapshot from `logStream` (XPC FileHandle
        // reads from byte 0 — no incremental-only attach mode on the pinned revision). Clear
        // before consuming so filter toggles, Logs↔Overview round trips, and reconnects do not
        // accrete duplicate display rows.
        buffer.clear()
        bufferRevision += 1

        streamGeneration += 1
        let generation = streamGeneration
        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeStream(generation: generation)
        }
    }

    private func consumeStream(generation: UInt64) async {
        isStreamActive = true
        defer {
            // Stale consumers must not mark the active attach finished / inactive.
            if generation == streamGeneration {
                isStreamActive = false
                isStreamFinished = true
                bufferRevision += 1
            }
        }

        let stream = service.logStream(id: containerID, source: sourceFilter.logSource)
        do {
            for try await chunk in stream {
                guard !Task.isCancelled, generation == streamGeneration else { return }
                guard !isPaused else { continue }
                buffer.append(chunk: chunk)
                bufferRevision += 1
                if !isTailPinned {
                    hasUnseenLinesWhileUnpinned = true
                }
            }
        } catch {
            return
        }

        if !Task.isCancelled && containerIsRunning && generation == streamGeneration {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled && containerIsRunning && generation == streamGeneration else { return }
            restartStream()
        }
    }
}
