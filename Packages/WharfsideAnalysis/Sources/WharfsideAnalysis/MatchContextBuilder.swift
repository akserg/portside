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
    /// Historical name; since B8.2 boot evidence is always collected — this value means
    /// "stdio present, boot appended." Renaming has rulebook signing implications; leave the
    /// wire string alone.
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
        let scopedBoot = BootLogCycleSegmenter.finalCycleEntries(from: split.boot)
        // logLines and errorLineCount share the same window so `maxErrorCount` keys on
        // exactly the lines the rule sees (I5 single-window discipline).
        let windowEntries = matchEntries(
            sourceMode: sourceMode,
            stdio: split.stdio,
            scopedBoot: scopedBoot
        )

        return MatchContext(
            image: context.image,
            exitCode: context.exitStatus.knownCode.map(Int.init),
            source: sourceMode.ruleIdentifier,
            logLines: windowEntries.map(\.raw),
            errorLineCount: windowEntries.filter { $0.level == .error }.count
        )
    }

    public static func digestSourceMode(stdio: [LogEntry], boot: [LogEntry]) -> DigestSourceMode {
        if stdio.isEmpty, !boot.isEmpty { return .bootLogOnly }
        if boot.isEmpty { return .stdio }
        return .stdioWithBootFallback
    }

    private static func matchEntries(
        sourceMode: DigestSourceMode,
        stdio: [LogEntry],
        scopedBoot: [LogEntry]
    ) -> [LogEntry] {
        switch sourceMode {
        case .bootLogOnly:
            return scopedBoot
        case .stdio:
            return stdio
        case .stdioWithBootFallback:
            return stdio + scopedBoot
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
