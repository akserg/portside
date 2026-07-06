import Foundation

/// Replaces variable segments in log messages with stable placeholders for clustering.
public struct MessageNormalizer: Sendable {
  /// A single normalization pass applied in declaration order.
  public struct Rule: Sendable {
    public let pattern: String
    public let placeholder: String

    public init(pattern: String, placeholder: String) {
      self.pattern = pattern
      self.placeholder = placeholder
    }
  }

  /// Table-driven rules — add new rows here to extend normalization.
  public static let defaultRules: [Rule] = [
    Rule(
      pattern: #"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}"#,
      placeholder: "{uuid}"
    ),
    Rule(pattern: #"(?<!\w)(?:\d{1,3}\.){3}\d{1,3}:\d{1,5}(?!\w)"#, placeholder: "{ip}:{port}"),
    Rule(pattern: #"(?<!\w)(?:\d{1,3}\.){3}\d{1,3}(?!\w)"#, placeholder: "{ip}"),
    Rule(
      pattern: #"(?<!\w)(?:[0-9a-fA-F]{0,4}:){2,7}[0-9a-fA-F]{0,4}(?::\d{1,5})?(?!\w)"#,
      placeholder: "{ipv6}"
    ),
    Rule(
      pattern: #"\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:?\d{2})?"#,
      placeholder: "{timestamp}"
    ),
    Rule(pattern: #"(?<!\w)0x[0-9a-fA-F]{8,}(?!\w)"#, placeholder: "{hex}"),
    Rule(pattern: #"(?<!\w)[0-9a-fA-F]{8,}(?!\w)"#, placeholder: "{hex}"),
    Rule(pattern: #""[^"]*""#, placeholder: "{string}"),
    Rule(pattern: #"'[^']*'"#, placeholder: "{string}"),
    Rule(pattern: #"\b\d+(?:\.\d+)?\b"#, placeholder: "{n}")
  ]

  private struct CompiledRule {
    let regex: NSRegularExpression
    let placeholder: String
    let needsDigit: Bool
    let needsColon: Bool
    let needsQuote: Bool
    let needsDash: Bool
    let needsDot: Bool

    init(regex: NSRegularExpression, placeholder: String) {
      self.regex = regex
      self.placeholder = placeholder
      switch placeholder {
      case "{uuid}", "{timestamp}":
        needsDigit = true
        needsColon = true
        needsQuote = false
        needsDash = true
        needsDot = true
      case "{ip}:{port}", "{ip}":
        needsDigit = true
        needsColon = true
        needsQuote = false
        needsDash = false
        needsDot = true
      case "{ipv6}":
        needsDigit = true
        needsColon = true
        needsQuote = false
        needsDash = false
        needsDot = false
      case "{hex}":
        needsDigit = true
        needsColon = false
        needsQuote = false
        needsDash = false
        needsDot = false
      case "{string}":
        needsDigit = false
        needsColon = false
        needsQuote = true
        needsDash = false
        needsDot = false
      case "{n}":
        needsDigit = true
        needsColon = false
        needsQuote = false
        needsDash = false
        needsDot = true
      default:
        needsDigit = false
        needsColon = false
        needsQuote = false
        needsDash = false
        needsDot = false
      }
    }

    func mightApply(to string: String) -> Bool {
      if needsDigit && !string.contains(where: \.isNumber) { return false }
      if needsColon && !string.contains(":") { return false }
      if needsQuote && !string.contains("\"") && !string.contains("'") { return false }
      if needsDash && !string.contains("-") { return false }
      if needsDot && !string.contains(".") { return false }
      return true
    }
  }

  private let compiledRules: [CompiledRule]

  public init(rules: [Rule] = MessageNormalizer.defaultRules) {
    self.compiledRules = rules.compactMap { rule in
      guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return nil }
      return CompiledRule(regex: regex, placeholder: rule.placeholder)
    }
  }

  /// Returns a normalized template string suitable for pattern clustering.
  public func normalize(_ message: String) -> String {
    if message.isEmpty { return "{empty}" }

    var result = message
    for rule in compiledRules {
      if !rule.mightApply(to: result) { continue }
      let range = NSRange(result.startIndex..., in: result)
      result = rule.regex.stringByReplacingMatches(in: result, range: range, withTemplate: rule.placeholder)
    }
    return collapseWhitespace(result)
  }

  private func collapseWhitespace(_ string: String) -> String {
    string
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
