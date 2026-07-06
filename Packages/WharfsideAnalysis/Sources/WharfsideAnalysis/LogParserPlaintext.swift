import Foundation

extension LogParser {
  func parsePlaintextLine(_ line: String, context: LogParseContext) -> LogEntry {
    var remainder = line
    var timestamp: Date?

    if let (parsedDate, rest) = extractLeadingISOTimestamp(from: remainder, context: context) {
      timestamp = parsedDate
      remainder = rest
    }

    if let (parsedDate, rest) = extractBracketedTimestamp(from: remainder, context: context) {
      timestamp = parsedDate
      remainder = rest
    }

    if let (parsedDate, rest) = extractSyslogTimestamp(from: remainder, context: context) {
      timestamp = parsedDate
      remainder = rest
    }

    if let (parsedDate, rest) = extractDateCommandTimestamp(from: remainder, context: context) {
      timestamp = parsedDate
      remainder = rest
    }

    remainder = peelTimezoneAndYearPrefix(from: remainder)
    remainder = remainder.trimmingCharacters(in: .whitespaces)

    if let (level, message) = extractBracketedLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    if let (level, message) = extractColonPrefixedLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    if let (level, message) = extractSpacedLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    if let (level, message) = extractPostgresLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    if let (level, message) = extractJVMLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    if let (level, message) = extractExceptionLevel(from: remainder, context: context) {
      return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
    }

    return LogEntry(timestamp: timestamp, level: .unknown, message: remainder.isEmpty ? line : remainder, raw: line)
  }

  func regexMatch(
    _ regex: NSRegularExpression,
    in line: String,
    groupCount: Int
  ) -> [String]? {
    guard let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) else {
      return nil
    }
    var groups: [String] = []
    groups.reserveCapacity(groupCount)
    for index in 1...groupCount {
      guard let range = Range(match.range(at: index), in: line) else { return nil }
      groups.append(String(line[range]))
    }
    return groups
  }

  func extractLeadingISOTimestamp(from line: String, context: LogParseContext) -> (Date, String)? {
    if let peeled = TimestampParsing.peelLeadingTimestamp(from: line) {
      return peeled
    }

    guard let match = regexMatch(context.leadingISOTimestamp, in: line, groupCount: 1) else { return nil }
    guard let date = parseTimestampString(match[0], context: context) else { return nil }
    guard let fullRange = Range(
      context.leadingISOTimestamp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))!.range,
      in: line
    ) else { return nil }
    return (date, String(line[fullRange.upperBound...]))
  }

  func extractBracketedTimestamp(from line: String, context: LogParseContext) -> (Date, String)? {
    guard let match = regexMatch(context.bracketedTimestamp, in: line, groupCount: 1) else { return nil }
    guard let date = parseTimestampString(match[0], context: context) else { return nil }
    guard let fullRange = Range(
      context.bracketedTimestamp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))!.range,
      in: line
    ) else { return nil }
    return (date, String(line[fullRange.upperBound...]))
  }

  func extractSyslogTimestamp(from line: String, context: LogParseContext) -> (Date, String)? {
    guard let match = regexMatch(context.syslogTimestamp, in: line, groupCount: 1) else { return nil }
    let timestampString = match[0]
    guard let fullRange = Range(
      context.syslogTimestamp.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))!.range,
      in: line
    ) else { return nil }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "MMM d HH:mm:ss"
    formatter.timeZone = TimeZone.current
    let year = Calendar.current.component(.year, from: Date())
    let date = formatter.date(from: "\(timestampString) \(year)")

    return (date ?? Date(timeIntervalSince1970: 0), String(line[fullRange.upperBound...]))
  }

  func extractDateCommandTimestamp(from line: String, context: LogParseContext) -> (Date, String)? {
    guard let match = context.dateCommandTimestamp.firstMatch(
      in: line,
      range: NSRange(line.startIndex..., in: line)
    ),
      let range = Range(match.range, in: line) else { return nil }

    let token = String(line[range])
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "EEE MMM d HH:mm:ss"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    let trimmed = token.trimmingCharacters(in: .whitespaces)
    let date = formatter.date(from: trimmed)

    return (date ?? Date(timeIntervalSince1970: 0), String(line[range.upperBound...]))
  }

  /// Strips `date`-command suffixes like `UTC 2026` between syslog timestamps and level tokens.
  func peelTimezoneAndYearPrefix(from line: String) -> String {
    var remainder = line
    let patterns = [
      #"^(?:UTC|GMT)\s+\d{4}\s+"#,
      #"^(?:UTC|GMT)\s+"#,
      #"^\d{4}\s+"#
    ]
    for pattern in patterns {
      guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
      guard let match = regex.firstMatch(in: remainder, range: NSRange(remainder.startIndex..., in: remainder)),
            let range = Range(match.range, in: remainder) else { continue }
      remainder = String(remainder[range.upperBound...])
      break
    }
    return remainder
  }

  func extractSpacedLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.spacedLevel, in: line, groupCount: 2) else { return nil }
    return (LogLevel.from(match[0]), match[1])
  }

  func extractBracketedLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.bracketedLevel, in: line, groupCount: 2) else { return nil }
    let levelToken = match[0]
    guard LogLevel.from(levelToken) != .unknown || isKnownLevelToken(levelToken) else { return nil }
    return (LogLevel.from(levelToken), match[1])
  }

  func extractColonPrefixedLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.colonPrefixedLevel, in: line, groupCount: 2) else { return nil }
    return (LogLevel.from(match[0]), match[1])
  }

  func extractPostgresLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.postgresLevel, in: line, groupCount: 2) else { return nil }
    let token = match[0].uppercased()
    let level: LogLevel = switch token {
    case "FATAL", "PANIC", "ERROR": .error
    case "WARNING": .warn
    case "NOTICE", "INFO", "LOG": .info
    case "DETAIL", "HINT": .debug
    default: .unknown
    }
    return (level, match[1])
  }

  func extractJVMLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.jvmLevel, in: line, groupCount: 2) else { return nil }
    let token = match[0].uppercased()
    let level: LogLevel = switch token {
    case "SEVERE": .error
    case "WARNING": .warn
    case "INFO", "CONFIG": .info
    case "FINE": .debug
    case "FINER", "FINEST": .trace
    default: .unknown
    }
    return (level, match[1])
  }

  func extractExceptionLevel(from line: String, context: LogParseContext) -> (LogLevel, String)? {
    guard let match = regexMatch(context.exceptionLine, in: line, groupCount: 3) else { return nil }
    let message = match[2].isEmpty ? line : "\(match[0]): \(match[2])"
    return (.error, message)
  }

  func parseTimestampValue(_ value: Any, context: LogParseContext) -> Date? {
    if let string = value as? String {
      return parseTimestampString(string, context: context)
    }
    if let number = value as? Double {
      return dateFromEpoch(number)
    }
    if let number = value as? Int {
      return dateFromEpoch(Double(number))
    }
    return nil
  }

  func parseTimestampString(_ string: String, context: LogParseContext) -> Date? {
    if let date = TimestampParsing.parseFractionalUTC(string) { return date }
    if let date = TimestampParsing.parseCompactUTC(string) { return date }
    if let date = context.iso8601Fractional.date(from: string) { return date }
    if let date = context.iso8601Basic.date(from: string) { return date }

    if let numeric = Double(string) {
      return dateFromEpoch(numeric)
    }

    return nil
  }

  func dateFromEpoch(_ value: Double) -> Date {
    if value > 1_000_000_000_000 {
      return Date(timeIntervalSince1970: value / 1000)
    }
    return Date(timeIntervalSince1970: value)
  }

  func isKnownLevelToken(_ token: String) -> Bool {
    let upper = token.uppercased()
    return ["ERROR", "WARN", "WARNING", "INFO", "DEBUG", "TRACE", "FATAL", "PANIC", "SEVERE"].contains(upper)
  }
}
