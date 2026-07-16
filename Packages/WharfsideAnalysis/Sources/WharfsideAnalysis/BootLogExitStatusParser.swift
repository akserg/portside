import Foundation

/// Parses init-process exit evidence from **boot-source log lines only** (`LogSource.boot`).
///
/// Anchored to `Docs/OBSERVED_STOP_SIGNATURE.md`: scopes to the **final lifecycle cycle**,
/// then resolves the sole terminal `status: <code> managed process exit` line. The
/// SIGTERM (15) → SIGKILL (9) sequence is the stop-request signature that
/// `precheck.stop-escalation` keys on — it is *not* required to resolve the exit code
/// itself (a `sh -c 'exit 1'` container exits with a bare `status: 1` line and no signals).
/// Fails closed on ambiguity within that cycle (two status lines with no intervening
/// terminal boundary → `.ambiguousEvidence`).
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

    // A single, unambiguous terminal status line resolves the exit code regardless of
    // whether the SIGTERM/SIGKILL sequence preceded it. The signal sequence is the
    // stop-request evidence for `precheck.stop-escalation`, not a precondition for
    // reading the exit code.
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
}
