import Foundation

/// Renders a `LogDigest` into compact plain text for the FoundationModels prompt.
public struct PromptRenderer: Sendable {
    public init() {}

    /// Produces a deterministic, labeled plain-text block (no markdown).
    public func render(_ digest: LogDigest) -> String {
        var sections: [String] = []
        appendHeaderSections(for: digest, to: &sections)
        appendEvidenceSections(for: digest, to: &sections)
        appendTailSections(for: digest, to: &sections)
        return sections.joined(separator: "\n")
    }

    private func appendHeaderSections(for digest: LogDigest, to sections: inout [String]) {
        sections.append("CONTAINER: \(digest.containerName)")
        sections.append("IMAGE: \(digest.image)")
        if let exitLine = digest.exitStatus.digestExitLine {
            sections.append(exitLine)
        }
        sections.append("WINDOW: \(digest.windowDescription)")
        sections.append("RESTARTS: \(digest.restartCount)")
        if let sourceNote = digest.sourceNote {
            sections.append("SOURCE: \(sourceNote)")
        }

        if !digest.facts.isEmpty {
            sections.append("FACTS:")
            sections.append(contentsOf: digest.facts)
        }

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
    }

    private func appendEvidenceSections(for digest: LogDigest, to sections: inout [String]) {
        if let firstError = digest.firstError {
            sections.append("FIRST_ERROR:")
            sections.append(firstError)
        }

        if let lastError = digest.lastError {
            sections.append("LAST_ERROR:")
            sections.append(lastError)
        }

        if !digest.topPatterns.isEmpty {
            sections.append("TOP_PATTERNS:")
            let timestampFormatter = ISO8601DateFormatter()
            timestampFormatter.formatOptions = [.withInternetDateTime]
            for (index, pattern) in digest.topPatterns.enumerated() {
                let first = timestampFormatter.string(from: pattern.firstSeen)
                let last = timestampFormatter.string(from: pattern.lastSeen)
                sections.append(
                    "\(index + 1). [\(pattern.count)x] \(pattern.template) (first=\(first), last=\(last))"
                )
            }
        }
    }

    private func appendTailSections(for digest: LogDigest, to sections: inout [String]) {
        if !digest.lastLines.isEmpty {
            sections.append("LAST_LINES:")
            sections.append(contentsOf: digest.lastLines)
        }

        if !digest.bootLines.isEmpty {
            sections.append("BOOT_LOG (runtime init, usually not the app's crash cause):")
            sections.append(contentsOf: digest.bootLines)
        }
    }
}
