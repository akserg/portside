import Foundation

/// Splits vminitd boot logs into lifecycle cycles for exit evidence, MatchContext, and digest.
///
/// See `docs/OBSERVED_STOP_SIGNATURE.md`. Diagnosis asks why the container died *most
/// recently*, so all consumers share one final-cycle window.
///
/// A cycle runs from just after the previous cycle's terminal line
/// (`status: N managed process exit`) — or the start of the log — through the end of
/// the buffer after its own terminal (includes VM boot preamble *before*
/// `started managed process`, and teardown after exit). `started managed process`
/// marks process launch, not cycle start.
enum BootLogCycleSegmenter {
    /// Terminal line of one init lifecycle (exit evidence + cycle boundary).
    private static let terminalPattern: NSRegularExpression = {
        guard let regex = try? NSRegularExpression(
            pattern: #"status:\s*\d+\s+managed process exit"#
        ) else {
            fatalError("BootLogCycleSegmenter: invalid terminal pattern")
        }
        return regex
    }()

    static func isCycleTerminal(_ line: String) -> Bool {
        let range = NSRange(line.startIndex..., in: line)
        return terminalPattern.firstMatch(in: line, range: range) != nil
    }

    /// Boot-source raw lines belonging to the most recent lifecycle cycle.
    static func finalCycleLines(from bootLines: [String]) -> [String] {
        let range = finalCycleIndexRange(lineCount: bootLines.count) { index in
            isCycleTerminal(bootLines[index])
        }
        guard let range else { return bootLines }
        return Array(bootLines[range])
    }

    /// Boot-source entries belonging to the most recent lifecycle cycle.
    static func finalCycleEntries(from bootEntries: [LogEntry]) -> [LogEntry] {
        let range = finalCycleIndexRange(lineCount: bootEntries.count) { index in
            isCycleTerminal(bootEntries[index].raw)
        }
        guard let range else { return bootEntries }
        return Array(bootEntries[range])
    }

    /// `nil` means "no terminal found — use the full buffer" (caller keeps all lines;
    /// exit parser fail-closes on missing status).
    private static func finalCycleIndexRange(
        lineCount: Int,
        isTerminal: (Int) -> Bool
    ) -> Range<Int>? {
        guard lineCount > 0 else { return nil }
        let terminals = (0..<lineCount).filter(isTerminal)
        guard !terminals.isEmpty else { return nil }
        let start = terminals.dropLast().last.map { $0 + 1 } ?? 0
        // Through end of buffer so final-cycle teardown (relay close, unmount) stays in-window.
        return start..<lineCount
    }
}
