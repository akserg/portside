import Foundation
import RulebookCore

extension LogSource {
    /// Wire identifier for `MatchCriteria.sources` (RULEBOOK_INTEGRATION.md §4.1).
    public var ruleIdentifier: String {
        switch self {
        case .stdio: "stdio"
        case .boot: "boot"
        }
    }
}

/// Digest-level source mode sent to the rule engine.
public enum DigestSourceMode: String, Sendable, Equatable {
    case stdio
    case bootLogOnly
    case stdioWithBootFallback

    public var ruleIdentifier: String { rawValue }
}

public enum MatchContextBuilder {

    /// Projects container + log window into the rule engine's match context.
    /// Boot log patterns are scoped to the final lifecycle cycle per OBSERVED_STOP_SIGNATURE.md.
    public static func make(
        entries: [LogEntry],
        context: ContainerContext
    ) -> MatchContext {
        let split = splitEntriesBySource(entries)
        let sourceMode = digestSourceMode(stdio: split.stdio, boot: split.boot)
        let bootLines = split.boot.map(\.raw)
        let scopedBoot = BootLogCycleSegmenter.finalCycleLines(from: bootLines)
        let logLines = matchLines(
            sourceMode: sourceMode,
            stdio: split.stdio,
            scopedBoot: scopedBoot
        )

        return MatchContext(
            image: context.image,
            exitCode: context.exitStatus.knownCode.map(Int.init),
            source: sourceMode.ruleIdentifier,
            logLines: logLines
        )
    }

    public static func digestSourceMode(stdio: [LogEntry], boot: [LogEntry]) -> DigestSourceMode {
        if stdio.isEmpty, !boot.isEmpty { return .bootLogOnly }
        if boot.isEmpty { return .stdio }
        return .stdioWithBootFallback
    }

    private static func matchLines(
        sourceMode: DigestSourceMode,
        stdio: [LogEntry],
        scopedBoot: [String]
    ) -> [String] {
        switch sourceMode {
        case .bootLogOnly:
            return scopedBoot
        case .stdio:
            return stdio.map(\.raw)
        case .stdioWithBootFallback:
            return stdio.map(\.raw) + scopedBoot
        }
    }

    private static func splitEntriesBySource(_ entries: [LogEntry]) -> (stdio: [LogEntry], boot: [LogEntry]) {
        var stdio: [LogEntry] = []
        var boot: [LogEntry] = []
        for entry in entries {
            switch entry.source {
            case .stdio: stdio.append(entry)
            case .boot: boot.append(entry)
            }
        }
        return (stdio, boot)
    }
}
