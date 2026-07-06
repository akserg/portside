import Foundation

/// Windowed log statistics used when assembling a digest.
public struct WindowStatistics: Sendable, Equatable {
    public let counts: [String: Int]
    public let firstError: String?
    public let lastLines: [String]
    public let errorSpikeDetected: Bool

    public init(
        counts: [String: Int],
        firstError: String?,
        lastLines: [String],
        errorSpikeDetected: Bool
    ) {
        self.counts = counts
        self.firstError = firstError
        self.lastLines = lastLines
        self.errorSpikeDetected = errorSpikeDetected
    }

    /// Computes statistics for entries within an optional time window.
    public static func compute(
        entries: [LogEntry],
        window: DigestWindow,
        lastLinesCount: Int,
        spikeConfig: SpikeDetectionConfig = SpikeDetectionConfig()
    ) -> WindowStatistics {
        let filtered = filter(entries: entries, window: window)
        let counts = severityCounts(for: filtered)
        let firstError = filtered.first(where: { $0.level == .error })?.raw
        let lastLines = Array(filtered.suffix(lastLinesCount).map(\.raw))
        let spike = detectErrorSpike(in: filtered, config: spikeConfig)

        return WindowStatistics(
            counts: counts,
            firstError: firstError,
            lastLines: lastLines,
            errorSpikeDetected: spike
        )
    }

    private static func filter(entries: [LogEntry], window: DigestWindow) -> [LogEntry] {
        guard window.start != nil || window.end != nil else { return entries }

        return entries.filter { entry in
            guard let timestamp = entry.timestamp else { return true }
            if let start = window.start, timestamp < start { return false }
            if let end = window.end, timestamp > end { return false }
            return true
        }
    }

    private static func severityCounts(for entries: [LogEntry]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for level in LogLevel.allCases {
            counts[level.label] = 0
        }

        for entry in entries {
            counts[entry.level.label, default: 0] += 1
        }

        return counts
    }

    private static func detectErrorSpike(in entries: [LogEntry], config: SpikeDetectionConfig) -> Bool {
        var timestamps: [Date] = []
        timestamps.reserveCapacity(min(entries.count, 256))
        for entry in entries where entry.level == .error {
            if let timestamp = entry.timestamp {
                timestamps.append(timestamp)
            }
        }
        guard timestamps.count >= config.minimumRecentErrors else { return false }

        timestamps.sort()
        guard let latest = timestamps.last else { return false }

        let recentStart = latest.addingTimeInterval(-config.recentWindowMinutes * 60)
        var recentErrors = 0
        var baselineErrors = 0
        for timestamp in timestamps {
            if timestamp >= recentStart {
                recentErrors += 1
            } else {
                baselineErrors += 1
            }
        }
        guard recentErrors >= config.minimumRecentErrors else { return false }

        let baselineDurationMinutes = max(
            config.recentWindowMinutes,
            (recentStart.timeIntervalSince(timestamps.first ?? recentStart)) / 60
        )
        let baselineRate = Double(baselineErrors) / baselineDurationMinutes
        let recentRate = Double(recentErrors) / config.recentWindowMinutes

        if baselineRate == 0 {
            return recentRate > 0
        }

        return recentRate >= baselineRate * config.baselineMultiplierThreshold
    }
}
