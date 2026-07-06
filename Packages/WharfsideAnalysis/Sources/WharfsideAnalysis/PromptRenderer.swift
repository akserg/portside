import Foundation

/// Renders a `LogDigest` into compact plain text for the FoundationModels prompt.
public struct PromptRenderer: Sendable {
    public init() {}

    /// Produces a deterministic, labeled plain-text block (no markdown).
    public func render(_ digest: LogDigest) -> String {
        let timestampFormatter = ISO8601DateFormatter()
        timestampFormatter.formatOptions = [.withInternetDateTime]

        var sections: [String] = []

        sections.append("CONTAINER: \(digest.containerName)")
        sections.append("IMAGE: \(digest.image)")
        if let exitCode = digest.exitCode {
            sections.append("EXIT_CODE: \(exitCode)")
        }
        sections.append("WINDOW: \(digest.windowDescription)")
        sections.append("RESTARTS: \(digest.restartCount)")

        let countLine = digest.counts
            .sorted { $0.key < $1.key }
            .filter { $0.value > 0 }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: " ")
        if !countLine.isEmpty {
            sections.append("COUNTS: \(countLine)")
        }

        if digest.errorSpikeDetected {
            sections.append("ERROR_SPIKE: yes")
        }

        if let firstError = digest.firstError {
            sections.append("FIRST_ERROR:")
            sections.append(firstError)
        }

        if !digest.topPatterns.isEmpty {
            sections.append("TOP_PATTERNS:")
            for (index, pattern) in digest.topPatterns.enumerated() {
                let first = timestampFormatter.string(from: pattern.firstSeen)
                let last = timestampFormatter.string(from: pattern.lastSeen)
                sections.append(
                    "\(index + 1). [\(pattern.count)x] \(pattern.template) (first=\(first), last=\(last))"
                )
            }
        }

        if !digest.lastLines.isEmpty {
            sections.append("LAST_LINES:")
            sections.append(contentsOf: digest.lastLines)
        }

        return sections.joined(separator: "\n")
    }
}
