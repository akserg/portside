import Foundation

/// Precompiled formatters and regexes reused across a single parse pass.
struct LogParseContext {
  let iso8601Fractional: ISO8601DateFormatter
  let iso8601Basic: ISO8601DateFormatter
  let leadingISOTimestamp: NSRegularExpression
  let bracketedTimestamp: NSRegularExpression
  let syslogTimestamp: NSRegularExpression
  let bracketedLevel: NSRegularExpression
  let colonPrefixedLevel: NSRegularExpression
  let postgresLevel: NSRegularExpression
  let jvmLevel: NSRegularExpression
  let exceptionLine: NSRegularExpression

  init() {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    iso8601Fractional = fractional

    let basic = ISO8601DateFormatter()
    basic.formatOptions = [.withInternetDateTime]
    iso8601Basic = basic

    leadingISOTimestamp = Self.regex(
      #"^(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\s+"#
    )
    bracketedTimestamp = Self.regex(
      #"^\[(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?)\]\s+"#
    )
    syslogTimestamp = Self.regex(
      #"^([A-Z][a-z]{2}\s+\d{1,2}\s+\d{2}:\d{2}:\d{2})\s+"#
    )
    bracketedLevel = Self.regex(#"^\[([A-Za-z]+)\]\s*:?\s*(.*)$"#)
    colonPrefixedLevel = Self.regex(
      #"^(ERROR|WARN(?:ING)?|INFO|DEBUG|TRACE|FATAL|PANIC|SEVERE)\s*:\s*(.*)$"#,
      options: .caseInsensitive
    )
    postgresLevel = Self.regex(
      #"^(LOG|INFO|NOTICE|WARNING|ERROR|FATAL|PANIC|DETAIL|HINT):\s+(.*)$"#,
      options: .caseInsensitive
    )
    jvmLevel = Self.regex(
      #"^(SEVERE|WARNING|INFO|CONFIG|FINE|FINER|FINEST)\s+(.*)$"#,
      options: .caseInsensitive
    )
    exceptionLine = Self.regex(
      #"^([a-z][\w.$]*(Exception|Error)):\s*(.*)$"#
    )
  }

  private static func regex(
    _ pattern: String,
    options: NSRegularExpression.Options = []
  ) -> NSRegularExpression {
    guard let compiled = try? NSRegularExpression(pattern: pattern, options: options) else {
      preconditionFailure("Invalid log parser regex: \(pattern)")
    }
    return compiled
  }
}
