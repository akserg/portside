import Foundation

/// Clusters log entries by normalized message template.
public struct PatternClusterer: Sendable {
  private let normalizer: MessageNormalizer

  public init(normalizer: MessageNormalizer = MessageNormalizer()) {
    self.normalizer = normalizer
  }

  /// Groups entries into `LogPattern` clusters sorted by count descending, then template ascending.
  public func cluster(entries: [LogEntry]) -> [LogPattern] {
    struct Accumulator {
      var count: Int = 0
      var firstSeen: Date?
      var lastSeen: Date?
      var sampleRaw: String = ""
    }

    var buckets: [String: Accumulator] = [:]

    for entry in entries {
      let template = normalizer.normalize(entry.message)
      var bucket = buckets[template] ?? Accumulator()
      bucket.count += 1
      if bucket.sampleRaw.isEmpty {
        bucket.sampleRaw = entry.raw
      }
      if let timestamp = entry.timestamp {
        if bucket.firstSeen == nil || timestamp < bucket.firstSeen! {
          bucket.firstSeen = timestamp
        }
        if bucket.lastSeen == nil || timestamp > bucket.lastSeen! {
          bucket.lastSeen = timestamp
        }
      }
      buckets[template] = bucket
    }

    let epoch = Date(timeIntervalSince1970: 0)

    return buckets
      .map { template, bucket in
        LogPattern(
          template: template,
          count: bucket.count,
          firstSeen: bucket.firstSeen ?? epoch,
          lastSeen: bucket.lastSeen ?? epoch,
          sampleRaw: bucket.sampleRaw
        )
      }
      .sorted {
        if $0.count != $1.count { return $0.count > $1.count }
        return $0.template < $1.template
      }
  }
}
