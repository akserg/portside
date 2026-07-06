// Models/LogRingBuffer.swift

import Foundation
import WharfsideAnalysis

struct BufferedLogLine: Identifiable, Sendable, Equatable {
    let id: UInt64
    let text: String
    let source: LogSource
    let level: LogLevel
    let receivedAt: Date
    let entry: LogEntry
}

/// Fixed-capacity ring buffer of parsed log lines for the log viewer.
///
/// Lives in the app target (not `WharfsideAnalysis`) because it is UI streaming state —
/// retention policy and partial-line reassembly are viewer concerns, not digestion.
struct LogRingBuffer: Sendable {
    static let defaultCapacity = 100_000

    private(set) var lines: [BufferedLogLine] = []
    private var nextSequence: UInt64 = 1
    private var partialLineBySource: [LogSource: String] = [:]
    private let capacity: Int
    private let parser = LogParser()

    init(capacity: Int = LogRingBuffer.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    var count: Int { lines.count }

    mutating func append(chunk: LogChunk, receivedAt: Date = .now) {
        let text = String(data: chunk.data, encoding: .utf8) ?? ""
        guard !text.isEmpty else { return }

        let combined = (partialLineBySource[chunk.source] ?? "") + text
        var parts = combined.components(separatedBy: "\n")

        if combined.hasSuffix("\n") {
            partialLineBySource[chunk.source] = nil
            if parts.last == "" {
                parts.removeLast()
            }
        } else {
            partialLineBySource[chunk.source] = parts.popLast() ?? ""
        }

        for line in parts {
            appendLine(line, source: chunk.source, receivedAt: receivedAt)
        }
    }

    mutating func clear() {
        lines.removeAll(keepingCapacity: true)
        partialLineBySource.removeAll()
    }

    func filtered(
        search: String,
        sources: LogViewSourceFilter
    ) -> (lines: [BufferedLogLine], matchCount: Int) {
        let trimmedSearch = search.trimmingCharacters(in: .whitespacesAndNewlines)
        var matches: [BufferedLogLine] = []
        matches.reserveCapacity(lines.count)
        var matchCount = 0

        for line in lines where sources.includes(line.source) {
            if trimmedSearch.isEmpty {
                matches.append(line)
                continue
            }
            if line.text.localizedCaseInsensitiveContains(trimmedSearch) {
                matches.append(line)
                matchCount += 1
            }
        }

        return (matches, matchCount)
    }

    /// Parsed entries received within `window` of `now`.
    ///
    /// Intended for issue 1.6 (`LogDiagnosisService`): pass a digest window such as
    /// `.seconds(300)` to collect recent ERROR/WARN context without re-parsing raw chunks.
    func recentEntries(within window: Duration, now: Date = .now) -> [LogEntry] {
        let cutoff = now.addingTimeInterval(-window.timeInterval)
        return lines
            .filter { $0.receivedAt >= cutoff }
            .map(\.entry)
    }

    private mutating func appendLine(_ line: String, source: LogSource, receivedAt: Date) {
        let entry = parser.parse(lines: [line]).first
            ?? LogEntry(timestamp: nil, level: .unknown, message: line, raw: line)
        let buffered = BufferedLogLine(
            id: nextSequence,
            text: line,
            source: source,
            level: entry.level,
            receivedAt: receivedAt,
            entry: entry
        )
        nextSequence += 1
        lines.append(buffered)
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        return TimeInterval(components.seconds)
            + TimeInterval(components.attoseconds) / 1_000_000_000_000_000_000
    }
}
