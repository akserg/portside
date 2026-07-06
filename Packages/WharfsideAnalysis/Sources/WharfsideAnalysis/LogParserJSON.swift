import Foundation

extension LogParser {
  static let levelKeys = ["level", "severity", "lvl", "loglevel", "log_level"]
  static let timestampKeys = ["time", "ts", "timestamp", "@timestamp", "datetime"]
  static let messageKeys = ["msg", "message", "log", "text", "error"]

  static let logfmtLeadingKeys: Set<String> = [
    "time", "level", "lvl", "severity", "msg", "message", "ts", "timestamp"
  ]

  func parseJSONLine(_ line: String, trimmed: String, context: LogParseContext) -> LogEntry? {
    guard let data = trimmed.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      return nil
    }

    let level = extractLevel(from: object) ?? .unknown
    let timestamp = extractTimestamp(from: object, context: context)
    let message = extractMessage(from: object) ?? trimmed

    return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
  }

  func parseLogfmtLine(_ line: String, trimmed: String, context: LogParseContext) -> LogEntry? {
    guard trimmed.contains("="), !trimmed.hasPrefix("{") else { return nil }
    guard let firstEquals = trimmed.firstIndex(of: "=") else { return nil }
    let firstKey = String(trimmed[..<firstEquals])
    guard Self.logfmtLeadingKeys.contains(firstKey) else { return nil }

    let fields = parseLogfmtFields(trimmed)
    guard !fields.isEmpty else { return nil }
    guard fields["level"] != nil || fields["msg"] != nil || fields["message"] != nil else { return nil }

    let level = fields["level"].map(LogLevel.from)
      ?? fields["lvl"].map(LogLevel.from)
      ?? fields["severity"].map(LogLevel.from)
      ?? .unknown

    let timestamp = fields["time"].flatMap { parseTimestampString($0, context: context) }
      ?? fields["ts"].flatMap { parseTimestampString($0, context: context) }
      ?? fields["timestamp"].flatMap { parseTimestampString($0, context: context) }

    let message = fields["msg"] ?? fields["message"] ?? trimmed

    return LogEntry(timestamp: timestamp, level: level, message: message, raw: line)
  }

  func parseLogfmtFields(_ line: String) -> [String: String] {
    var fields: [String: String] = [:]
    var index = line.startIndex

    while index < line.endIndex {
      while index < line.endIndex, line[index].isWhitespace {
        index = line.index(after: index)
      }
      guard index < line.endIndex else { break }

      guard let keyEnd = line[index...].firstIndex(of: "=") else { break }
      let key = String(line[index..<keyEnd])
      index = line.index(after: keyEnd)

      let value: String
      if index < line.endIndex, line[index] == "\"" {
        index = line.index(after: index)
        var buffer = ""
        var closed = false
        while index < line.endIndex {
          let character = line[index]
          if character == "\\", line.index(after: index) < line.endIndex {
            index = line.index(after: index)
            buffer.append(line[index])
          } else if character == "\"" {
            closed = true
            index = line.index(after: index)
            break
          } else {
            buffer.append(character)
          }
          index = line.index(after: index)
        }
        value = closed ? buffer : buffer
      } else {
        let valueStart = index
        while index < line.endIndex, !line[index].isWhitespace {
          index = line.index(after: index)
        }
        value = String(line[valueStart..<index])
      }

      fields[key] = value
    }

    return fields
  }

  func extractLevel(from object: [String: Any]) -> LogLevel? {
    for key in Self.levelKeys {
      if let value = object[key] {
        return levelFromJSONValue(value)
      }
    }
    return nil
  }

  func levelFromJSONValue(_ value: Any) -> LogLevel {
    if let string = value as? String {
      return LogLevel.from(string)
    }
    if let number = value as? Int {
      switch number {
      case 50...: return .error
      case 40: return .error
      case 30: return .warn
      case 20: return .info
      case 10: return .debug
      default: return .unknown
      }
    }
    return .unknown
  }

  func extractTimestamp(from object: [String: Any], context: LogParseContext) -> Date? {
    for key in Self.timestampKeys {
      if let value = object[key] {
        return parseTimestampValue(value, context: context)
      }
    }
    return nil
  }

  func extractMessage(from object: [String: Any]) -> String? {
    for key in Self.messageKeys {
      if let value = object[key] as? String, !value.isEmpty {
        return value
      }
    }
    return nil
  }
}
