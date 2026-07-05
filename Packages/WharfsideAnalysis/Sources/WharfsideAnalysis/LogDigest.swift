import Foundation

/// A clustered repeated log message with normalized placeholders.
public struct LogPattern: Sendable, Equatable {
    public let template: String
    public let count: Int
    public let firstSeen: Date
    public let lastSeen: Date

    public init(template: String, count: Int, firstSeen: Date, lastSeen: Date) {
        self.template = template
        self.count = count
        self.firstSeen = firstSeen
        self.lastSeen = lastSeen
    }
}

/// Deterministic summary of container logs for AI diagnosis (Layer 1).
public struct LogDigest: Sendable, Equatable {
    public let containerName: String
    public let image: String
    public let exitCode: Int32?
    public let windowDescription: String
    public let counts: [String: Int]
    public let topPatterns: [LogPattern]
    public let firstError: String?
    public let lastLines: [String]
    public let restartCount: Int

    public init(
        containerName: String,
        image: String,
        exitCode: Int32?,
        windowDescription: String,
        counts: [String: Int],
        topPatterns: [LogPattern],
        firstError: String?,
        lastLines: [String],
        restartCount: Int
    ) {
        self.containerName = containerName
        self.image = image
        self.exitCode = exitCode
        self.windowDescription = windowDescription
        self.counts = counts
        self.topPatterns = topPatterns
        self.firstError = firstError
        self.lastLines = lastLines
        self.restartCount = restartCount
    }
}
