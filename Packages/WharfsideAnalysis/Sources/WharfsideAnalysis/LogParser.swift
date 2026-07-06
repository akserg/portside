import Foundation

/// Parses raw log lines into structured `LogEntry` values. Never drops lines or throws.
public struct LogParser: Sendable {
  public init() {}

  /// Parses a multi-line log blob into entries, merging JVM stack-trace continuations.
  public func parse(text: String) -> [LogEntry] {
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    return parse(lines: lines)
  }

  /// Parses individual lines into entries, merging JVM stack-trace continuations.
  public func parse(lines: [String]) -> [LogEntry] {
    let context = LogParseContext()
    var entries: [LogEntry] = []
    entries.reserveCapacity(lines.count)

    for line in lines {
      if isContinuationLine(line), var previous = entries.popLast() {
        let mergedRaw = previous.raw + "\n" + line
        let mergedMessage = previous.message + "\n" + line.trimmingCharacters(in: .whitespaces)
        previous = LogEntry(
          timestamp: previous.timestamp,
          level: previous.level,
          message: mergedMessage,
          raw: mergedRaw
        )
        entries.append(previous)
        continue
      }

      entries.append(parseLine(line, context: context))
    }

    return entries
  }

  private func parseLine(_ line: String, context: LogParseContext) -> LogEntry {
    let trimmed = line.trimmingCharacters(in: .whitespaces)

    if trimmed.hasPrefix("{"), let entry = parseJSONLine(line, trimmed: trimmed, context: context) {
      return entry
    }

    if let entry = parseLogfmtLine(line, trimmed: trimmed, context: context) {
      return entry
    }

    return parsePlaintextLine(line, context: context)
  }

  private func isContinuationLine(_ line: String) -> Bool {
    let trimmed = line.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { return false }
    if trimmed.hasPrefix("at ") || trimmed.hasPrefix("at\t") { return true }
    if trimmed.hasPrefix("Caused by:") { return true }
    if trimmed.hasPrefix("...") { return true }
    if trimmed.hasPrefix("Suppressed:") { return true }
    if line.first?.isWhitespace == true, trimmed.contains(".java:") { return true }
    if trimmed.range(of: #"^[a-z][\w.$]*(Exception|Error):"#, options: .regularExpression) != nil {
      return true
    }
    return false
  }
}
