import Foundation

/// A clustered repeated log message with normalized placeholders.
public struct LogPattern: Sendable, Equatable {
    public let template: String
    public let count: Int
    public let firstSeen: Date
    public let lastSeen: Date
    /// One representative raw log line (or merged multi-line sample) from this cluster.
    public let sampleRaw: String

    public init(
        template: String,
        count: Int,
        firstSeen: Date,
        lastSeen: Date,
        sampleRaw: String
    ) {
        self.template = template
        self.count = count
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
        self.sampleRaw = sampleRaw
    }
}

/// Deterministic summary of container logs for AI diagnosis (Layer 1).
public struct LogDigest: Sendable, Equatable {
    public let containerName: String
    public let image: String
    public let exitStatus: ExitStatus
    public let windowDescription: String
    public let counts: [String: Int]
    public let topPatterns: [LogPattern]
    public let firstError: String?
    public let lastError: String?
    public let lastLines: [String]
    public let restartCount: Int
    /// Demoted boot-log tail when application (stdio) output is also present.
    public let bootLines: [String]
    /// Optional note when digest is boot-only (no stdio application output).
    public let sourceNote: String?
    /// Precheck facts from the rulebook (stable rulebook order).
    public let facts: [String]
    /// Whether error volume in the recent window exceeds the preceding baseline.
    public let errorSpikeDetected: Bool
    /// Approximate token count of the rendered prompt (`PromptRenderer`), using chars / 4.
    public let estimatedTokens: Int

    public init(
        containerName: String,
        image: String,
        exitStatus: ExitStatus,
        windowDescription: String,
        counts: [String: Int],
        topPatterns: [LogPattern],
        firstError: String?,
        lastError: String?,
        lastLines: [String],
        restartCount: Int,
        bootLines: [String] = [],
        sourceNote: String? = nil,
        facts: [String] = [],
        errorSpikeDetected: Bool = false,
        estimatedTokens: Int = 0
    ) {
        self.containerName = containerName
        self.image = image
        self.exitStatus = exitStatus
        self.windowDescription = windowDescription
        self.counts = counts
        self.topPatterns = topPatterns
        self.firstError = firstError
        self.lastError = lastError
        self.lastLines = lastLines
        self.restartCount = restartCount
        self.bootLines = bootLines
        self.sourceNote = sourceNote
        self.facts = facts
        self.errorSpikeDetected = errorSpikeDetected
        self.estimatedTokens = estimatedTokens
    }
}

/// Estimates token count from a rendered string (chars / 4).
public func estimatedTokens(for text: String) -> Int {
    max(1, text.count / 4)
}
