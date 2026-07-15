import Foundation
import RulebookCore

/// Assembles a token-budgeted `LogDigest` from parsed entries and container context.
public struct LogDigestBuilder: Sendable {
    public var tokenBudget: Int
    public var lastLinesCount: Int
    public var maxPatterns: Int
    public var spikeConfig: SpikeDetectionConfig
    public var bootTailLineCap: Int

    private let clusterer: PatternClusterer
    private let renderer: PromptRenderer

    public init(
        tokenBudget: Int = 1500,
        lastLinesCount: Int = 10,
        maxPatterns: Int = 100,
        spikeConfig: SpikeDetectionConfig = SpikeDetectionConfig(),
        bootTailLineCap: Int = 5,
        clusterer: PatternClusterer = PatternClusterer(),
        renderer: PromptRenderer = PromptRenderer()
    ) {
        self.tokenBudget = tokenBudget
        self.lastLinesCount = lastLinesCount
        self.maxPatterns = maxPatterns
        self.spikeConfig = spikeConfig
        self.bootTailLineCap = bootTailLineCap
        self.clusterer = clusterer
        self.renderer = renderer
    }

    /// Builds a digest with a single rule evaluation (I2 — evaluate once).
    public func buildWithRules(
        entries: [LogEntry],
        context: ContainerContext,
        window: DigestWindow,
        rulebookPipeline: RulebookPipeline = .load(rulebookData: nil)
    ) -> DigestBuildResult {
        let evaluation = rulebookPipeline.evaluate(entries: entries, context: context)
        let digest = build(
            entries: entries,
            context: context,
            window: window,
            evaluation: evaluation
        )
        return DigestBuildResult(
            digest: digest,
            evaluation: evaluation,
            rulebookVersion: rulebookPipeline.rulebook.version,
            rulebookSource: rulebookPipeline.source,
            fallbackReason: rulebookPipeline.fallbackReason,
            skippedUnknownKinds: rulebookPipeline.rulebook.skippedUnknownKinds
        )
    }

    /// Builds a digest from pre-parsed entries. Same input always yields byte-identical output.
    public func build(
        entries: [LogEntry],
        context: ContainerContext,
        window: DigestWindow,
        evaluation: RuleEvaluation = .empty
    ) -> LogDigest {
        let partition = partitionForDigest(entries, noisePatterns: evaluation.noisePatterns)
        let stats = WindowStatistics.compute(
            entries: partition.countEntries,
            window: window,
            lastLinesCount: lastLinesCount,
            spikeConfig: spikeConfig
        )

        let filtered = filterEntries(partition.clusterEntries, window: window)
        var patterns = clusterer.cluster(entries: filtered)
        if patterns.count > maxPatterns {
            patterns = Array(patterns.prefix(maxPatterns))
        }
        var lastLines = Array(filtered.suffix(lastLinesCount).map(\.raw))
        var demotedBootLines = partition.demotedBootLines

        var digest = makeDigest(
            context: context,
            window: window,
            stats: stats,
            content: DigestContent(
                patterns: patterns,
                lastLines: lastLines,
                bootLines: demotedBootLines,
                sourceNote: partition.sourceNote,
                facts: evaluation.facts
            )
        )

        return fitToTokenBudget(
            digest: &digest,
            patterns: &patterns,
            lastLines: &lastLines,
            bootLines: &demotedBootLines
        )
    }

    public func build(
        logText: String,
        context: ContainerContext,
        window: DigestWindow,
        parser: LogParser = LogParser(),
        evaluation: RuleEvaluation = .empty
    ) -> LogDigest {
        build(
            entries: parser.parse(text: logText),
            context: context,
            window: window,
            evaluation: evaluation
        )
    }

    private struct DigestPartition {
        let clusterEntries: [LogEntry]
        let countEntries: [LogEntry]
        let demotedBootLines: [String]
        let sourceNote: String?
    }

    private func partitionForDigest(
        _ entries: [LogEntry],
        noisePatterns: [String]
    ) -> DigestPartition {
        let split = splitEntriesBySource(entries)
        let useBootAsPrimary = split.stdio.isEmpty && !split.boot.isEmpty
        // Shared window with MatchContext / exit parser: final lifecycle cycle only.
        let scopedBoot = BootLogCycleSegmenter.finalCycleEntries(from: split.boot)
        let primaryEntries = useBootAsPrimary ? scopedBoot : split.stdio
        let sourceNote = useBootAsPrimary ? "boot log only (no application output)" : nil

        let clusterEntries = primaryEntries.filter { entry in
            !isNoiseBootLine(entry, patterns: noisePatterns)
        }

        let demotedBootLines: [String]
        if useBootAsPrimary || scopedBoot.isEmpty {
            demotedBootLines = []
        } else {
            demotedBootLines = Array(
                scopedBoot
                    .filter { !isNoiseBootLine($0, patterns: noisePatterns) }
                    .suffix(bootTailLineCap)
                    .map(\.raw)
            )
        }

        return DigestPartition(
            clusterEntries: clusterEntries,
            countEntries: primaryEntries,
            demotedBootLines: demotedBootLines,
            sourceNote: sourceNote
        )
    }

    private func isNoiseBootLine(_ entry: LogEntry, patterns: [String]) -> Bool {
        guard entry.source == .boot, !patterns.isEmpty else { return false }
        return RuleEngine.lineMatchesNoise(entry.raw, patterns: patterns)
    }

    private struct DigestContent {
        var patterns: [LogPattern]
        var lastLines: [String]
        var bootLines: [String]
        let sourceNote: String?
        let facts: [String]
    }

    private func makeDigest(
        context: ContainerContext,
        window: DigestWindow,
        stats: WindowStatistics,
        content: DigestContent
    ) -> LogDigest {
        LogDigest(
            containerName: context.containerName,
            image: context.image,
            exitStatus: context.exitStatus,
            windowDescription: window.description,
            counts: stats.counts,
            topPatterns: content.patterns,
            firstError: stats.firstError,
            lastError: stats.lastError,
            lastLines: content.lastLines,
            restartCount: context.restartCount,
            bootLines: content.bootLines,
            sourceNote: content.sourceNote,
            facts: content.facts,
            errorSpikeDetected: stats.errorSpikeDetected,
            estimatedTokens: 0
        )
    }

    private func fitToTokenBudget(
        digest: inout LogDigest,
        patterns: inout [LogPattern],
        lastLines: inout [String],
        bootLines: inout [String]
    ) -> LogDigest {
        var rendered = renderer.render(digest)
        var tokens = estimatedTokens(for: rendered)

        while tokens > tokenBudget {
            guard shrinkDigest(
                &digest,
                patterns: &patterns,
                lastLines: &lastLines,
                bootLines: &bootLines,
                tokens: tokens
            ) else { break }
            rendered = renderer.render(digest)
            tokens = estimatedTokens(for: rendered)
        }

        return LogDigest(
            containerName: digest.containerName,
            image: digest.image,
            exitStatus: digest.exitStatus,
            windowDescription: digest.windowDescription,
            counts: digest.counts,
            topPatterns: patterns,
            firstError: digest.firstError,
            lastError: digest.lastError,
            lastLines: lastLines,
            restartCount: digest.restartCount,
            bootLines: bootLines,
            sourceNote: digest.sourceNote,
            facts: digest.facts,
            errorSpikeDetected: digest.errorSpikeDetected,
            estimatedTokens: tokens
        )
    }

    private func splitEntriesBySource(_ entries: [LogEntry]) -> (stdio: [LogEntry], boot: [LogEntry]) {
        var stdio: [LogEntry] = []
        var boot: [LogEntry] = []
        stdio.reserveCapacity(entries.count)
        boot.reserveCapacity(entries.count / 4)
        for entry in entries {
            switch entry.source {
            case .stdio:
                stdio.append(entry)
            case .boot:
                boot.append(entry)
            }
        }
        return (stdio, boot)
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

    private func shrinkDigest(
        _ digest: inout LogDigest,
        patterns: inout [LogPattern],
        lastLines: inout [String],
        bootLines: inout [String],
        tokens: Int
    ) -> Bool {
        if patterns.count > 1 {
            let overshoot = tokens - tokenBudget
            let dropCount = max(1, min(patterns.count - 1, overshoot / 20))
            patterns.removeLast(dropCount)
            digest = copyDigest(digest, patterns: patterns, lastLines: lastLines, bootLines: bootLines)
            return true
        }

        if lastLines.count > 1 {
            lastLines.removeFirst()
            digest = copyDigest(digest, patterns: patterns, lastLines: lastLines, bootLines: bootLines)
            return true
        }

        if bootLines.count > 1 {
            bootLines.removeFirst()
            digest = copyDigest(digest, patterns: patterns, lastLines: lastLines, bootLines: bootLines)
            return true
        }

        return false
    }

    private func copyDigest(
        _ digest: LogDigest,
        patterns: [LogPattern],
        lastLines: [String],
        bootLines: [String]
    ) -> LogDigest {
        LogDigest(
            containerName: digest.containerName,
            image: digest.image,
            exitStatus: digest.exitStatus,
            windowDescription: digest.windowDescription,
            counts: digest.counts,
            topPatterns: patterns,
            firstError: digest.firstError,
            lastError: digest.lastError,
            lastLines: lastLines,
            restartCount: digest.restartCount,
            bootLines: bootLines,
            sourceNote: digest.sourceNote,
            facts: digest.facts,
            errorSpikeDetected: digest.errorSpikeDetected,
            estimatedTokens: digest.estimatedTokens
        )
    }
}
