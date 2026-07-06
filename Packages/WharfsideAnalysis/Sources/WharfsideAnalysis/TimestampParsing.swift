import Foundation

enum TimestampParsing {
  /// Parses `yyyy-MM-dd'T'HH:mm:ss'Z'` (20 chars) without using formatters.
  static func parseCompactUTC(_ string: String) -> Date? {
    let utf8 = Array(string.utf8)
    guard utf8.count == 20 else { return nil }
    guard utf8[4] == 45, utf8[7] == 45, utf8[10] == 84, utf8[13] == 58, utf8[16] == 58, utf8[19] == 90 else {
      return nil
    }

    guard let year = readInt(utf8, 0, 4),
          let month = readInt(utf8, 5, 2),
          let day = readInt(utf8, 8, 2),
          let hour = readInt(utf8, 11, 2),
          let minute = readInt(utf8, 14, 2),
          let second = readInt(utf8, 17, 2) else {
      return nil
    }

    var components = DateComponents()
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second
    components.timeZone = TimeZone(secondsFromGMT: 0)
    return Calendar(identifier: .gregorian).date(from: components)
  }

  /// Parses `yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` (24 chars) without using formatters.
  static func parseFractionalUTC(_ string: String) -> Date? {
    let utf8 = Array(string.utf8)
    guard utf8.count == 24 else { return nil }
    guard utf8[4] == 45, utf8[7] == 45, utf8[10] == 84, utf8[13] == 58, utf8[16] == 58,
          utf8[19] == 46, utf8[23] == 90 else {
      return nil
    }

    guard let base = parseCompactUTC(String(string.prefix(19)) + "Z") else { return nil }
    guard let millis = readInt(utf8, 20, 3) else { return nil }
    return base.addingTimeInterval(Double(millis) / 1000)
  }

  /// Extracts a leading ISO-8601 UTC timestamp and the remaining text.
  static func peelLeadingTimestamp(from line: String) -> (Date, String)? {
    if line.count >= 24, line[line.index(line.startIndex, offsetBy: 19)] == ".",
       let date = parseFractionalUTC(String(line.prefix(24))) {
      let rest = String(line[line.index(line.startIndex, offsetBy: 24)...]).trimmingCharacters(in: .whitespaces)
      return (date, rest)
    }

    if line.count >= 20, line[line.index(line.startIndex, offsetBy: 19)] == "Z",
       let date = parseCompactUTC(String(line.prefix(20))) {
      let rest = String(line[line.index(line.startIndex, offsetBy: 20)...]).trimmingCharacters(in: .whitespaces)
      return (date, rest)
    }

    return nil
  }

  private static func readInt(_ bytes: [UInt8], _ offset: Int, _ length: Int) -> Int? {
    var value = 0
    for index in offset..<(offset + length) {
      let byte = bytes[index]
      guard byte >= 48, byte <= 57 else { return nil }
      value = value * 10 + Int(byte - 48)
    }
    return value
  }
}
