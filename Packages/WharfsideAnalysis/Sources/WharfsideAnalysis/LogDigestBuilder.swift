import Foundation

/// Assembles a token-budgeted `LogDigest` from parsed entries and container context.
public struct LogDigestBuilder: Sendable {
    public var tokenBudget: Int
    public var lastLinesCount: Int
    /// Maximum patterns considered before token-budget trimming (prevents O(n²) renders).
    public var maxPatterns: Int
    public var spikeConfig: SpikeDetectionConfig

    private let clusterer: PatternClusterer
    private let renderer: PromptRenderer

    public init(
        tokenBudget: Int = 1500,
        lastLinesCount: Int = 10,
        maxPatterns: Int = 100,
        spikeConfig: SpikeDetectionConfig = SpikeDetectionConfig(),
        clusterer: PatternClusterer = PatternClusterer(),
        renderer: PromptRenderer = PromptRenderer()
    ) {
        self.tokenBudget = tokenBudget
        self.lastLinesCount = lastLinesCount
        self.maxPatterns = maxPatterns
        self.spikeConfig = spikeConfig
        self.clusterer = clusterer
        self.renderer = renderer
    }

    /// Builds a digest from pre-parsed entries. Same input always yields byte-identical output.
    public func build(
        entries: [LogEntry],
        context: ContainerContext,
        window: DigestWindow
    ) -> LogDigest {
        let stats = WindowStatistics.compute(
            entries: entries,
            window: window,
            lastLinesCount: lastLinesCount,
            spikeConfig: spikeConfig
        )

        let filtered = filterEntries(entries, window: window)
        var patterns = clusterer.cluster(entries: filtered)
        if patterns.count > maxPatterns {
            patterns = Array(patterns.prefix(maxPatterns))
        }
        var lastLines = stats.lastLines

        var digest = LogDigest(
            containerName: context.containerName,
            image: context.image,
            exitCode: context.exitCode,
            windowDescription: window.description,
            counts: stats.counts,
            topPatterns: patterns,
            firstError: stats.firstError,
            lastLines: lastLines,
            restartCount: context.restartCount,
            errorSpikeDetected: stats.errorSpikeDetected,
            estimatedTokens: 0
        )

        var rendered = renderer.render(digest)
        var tokens = estimatedTokens(for: rendered)

        while tokens > tokenBudget {
            guard shrinkDigest(&digest, patterns: &patterns, lastLines: &lastLines, tokens: tokens) else { break }
            rendered = renderer.render(digest)
            tokens = estimatedTokens(for: rendered)
        }

        return LogDigest(
            containerName: digest.containerName,
            image: digest.image,
            exitCode: digest.exitCode,
            windowDescription: digest.windowDescription,
            counts: digest.counts,
            topPatterns: patterns,
            firstError: digest.firstError,
            lastLines: lastLines,
            restartCount: digest.restartCount,
            errorSpikeDetected: digest.errorSpikeDetected,
            estimatedTokens: tokens
        )
    }

    /// Convenience: parse raw log text then build.
    public func build(
        logText: String,
        context: ContainerContext,
        window: DigestWindow,
        parser: LogParser = LogParser()
    ) -> LogDigest {
        build(entries: parser.parse(text: logText), context: context, window: window)
    }

    private func filterEntries(_ entries: [LogEntry], window: DigestWindow) -> [LogEntry] {
        guard window.start != nil || window.end != nil else { return entries }
        return entries.filter { entry in
            guard let timestamp = entry.timestamp else { return true }
            if let start = window.start, timestamp < start { return false }
            if let end = window.end, timestamp > end { return false }
            return true
        }
    }

    /// Returns false when no further reduction is possible.
    private func shrinkDigest(
        _ digest: inout LogDigest,
        patterns: inout [LogPattern],
        lastLines: inout [String],
        tokens: Int
    ) -> Bool {
        if patterns.count > 1 {
            let overshoot = tokens - tokenBudget
            let dropCount = max(1, min(patterns.count - 1, overshoot / 20))
            patterns.removeLast(dropCount)
            digest = copyDigest(digest, patterns: patterns, lastLines: lastLines)
            return true
        }

        if lastLines.count > 1 {
            lastLines.removeFirst()
            digest = copyDigest(digest, patterns: patterns, lastLines: lastLines)
            return true
        }

        return false
    }

    private func copyDigest(
        _ digest: LogDigest,
        patterns: [LogPattern],
        lastLines: [String]
    ) -> LogDigest {
        LogDigest(
            containerName: digest.containerName,
            image: digest.image,
            exitCode: digest.exitCode,
            windowDescription: digest.windowDescription,
            counts: digest.counts,
            topPatterns: patterns,
            firstError: digest.firstError,
            lastLines: lastLines,
            restartCount: digest.restartCount,
            errorSpikeDetected: digest.errorSpikeDetected,
            estimatedTokens: digest.estimatedTokens
        )
    }
}
