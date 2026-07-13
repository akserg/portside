import Foundation

/// Parses init-process exit evidence from **boot-source log lines only** (`LogSource.boot`).
///
/// Anchored to `Docs/OBSERVED_STOP_SIGNATURE.md`: scopes to the **final lifecycle cycle**,
/// then requires SIGTERM (15) → SIGKILL (9) → `status: <code> managed process exit`.
/// Fails closed on ambiguity within that cycle.
public struct BootLogExitStatusParser: Sendable {
  private let managedExitPattern: NSRegularExpression

  public init() {
    guard let regex = try? NSRegularExpression(
      pattern: #"status:\s*(\d+)\s+managed process exit"#
    ) else {
      fatalError("BootLogExitStatusParser: invalid managed exit pattern")
    }
    managedExitPattern = regex
  }

  public func parse(bootEntries: [LogEntry]) -> ExitStatus {
    let lines = bootEntries
      .filter { $0.source == .boot }
      .map(\.raw)

    guard !lines.isEmpty else {
      return .unavailable(reason: .noEvidence)
    }

    let cycleLines = BootLogCycleSegmenter.finalCycleLines(from: lines)
    return parseFinalCycle(lines: cycleLines)
  }

  /// Strict parse for a single lifecycle segment (one cycle of boot log).
  func parseFinalCycle(lines: [String]) -> ExitStatus {
    guard !lines.isEmpty else {
      return .unavailable(reason: .noEvidence)
    }

    var statusMatches: [(index: Int, code: Int32)] = []
    for (index, line) in lines.enumerated() {
      if let code = Self.parseManagedExitStatus(from: line, pattern: managedExitPattern) {
        statusMatches.append((index, code))
      }
    }

    guard !statusMatches.isEmpty else {
      return .unavailable(reason: .noEvidence)
    }

    guard statusMatches.count == 1, let sole = statusMatches.first else {
      return .unavailable(reason: .ambiguousEvidence)
    }

    let prefix = lines[0...sole.index]
    let hasSignal15 = prefix.contains { Self.lineSignalsSIGTERM($0) }
    let hasSignal9 = prefix.contains { Self.lineSignalsSIGKILL($0) }

    guard hasSignal15, hasSignal9 else {
      return .unavailable(reason: .ambiguousEvidence)
    }

    return .known(sole.code, source: .bootLog)
  }

  private static func parseManagedExitStatus(
    from line: String,
    pattern: NSRegularExpression
  ) -> Int32? {
    let range = NSRange(line.startIndex..., in: line)
    guard let match = pattern.firstMatch(in: line, range: range),
      match.numberOfRanges > 1,
      let codeRange = Range(match.range(at: 1), in: line),
      let code = Int32(line[codeRange])
    else { return nil }
    return code
  }

  private static func lineSignalsSIGTERM(_ line: String) -> Bool {
    line.contains("sending signal 15")
  }

  private static func lineSignalsSIGKILL(_ line: String) -> Bool {
    line.contains("sending signal 9")
  }
}
