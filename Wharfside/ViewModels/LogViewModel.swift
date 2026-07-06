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

        streamTask = Task { [weak self] in
            guard let self else { return }
            await self.consumeStream()
        }
    }

    private func consumeStream() async {
        isStreamActive = true
        defer {
            isStreamActive = false
            isStreamFinished = true
            bufferRevision += 1
        }

        let stream = service.logStream(id: containerID, source: sourceFilter.logSource)
        do {
            for try await chunk in stream {
                guard !Task.isCancelled else { return }
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

        if !Task.isCancelled && containerIsRunning {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled && containerIsRunning else { return }
            restartStream()
        }
    }
}
