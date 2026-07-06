import Foundation

/// Tunable parameters for error-rate spike detection.
public struct SpikeDetectionConfig: Sendable, Equatable {
    /// Duration of the recent window compared against the preceding baseline.
    public var recentWindowMinutes: Double
    /// Recent error rate must exceed baseline by this multiplier to flag a spike.
    public var baselineMultiplierThreshold: Double
    /// Minimum errors in the recent window required before a spike can be reported.
    public var minimumRecentErrors: Int

    public init(
        recentWindowMinutes: Double = 5,
        baselineMultiplierThreshold: Double = 3,
        minimumRecentErrors: Int = 5
    ) {
        self.recentWindowMinutes = recentWindowMinutes
        self.baselineMultiplierThreshold = baselineMultiplierThreshold
        self.minimumRecentErrors = minimumRecentErrors
    }
}
