import Foundation

/// Parsed severity of a single log line.
public enum LogLevel: String, Sendable, Equatable, CaseIterable, Comparable {
    case error
    case warn
    case info
    case debug
    case trace
    case unknown

    /// Canonical uppercase label used in digest counts and prompts.
    public var label: String {
        switch self {
        case .error: "ERROR"
        case .warn: "WARN"
        case .info: "INFO"
        case .debug: "DEBUG"
        case .trace: "TRACE"
        case .unknown: "UNKNOWN"
        }
    }

    /// Stable sort order for deterministic output (most severe first).
    public var severityRank: Int {
        switch self {
        case .error: 0
        case .warn: 1
        case .info: 2
        case .debug: 3
        case .trace: 4
        case .unknown: 5
        }
    }

    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        lhs.severityRank < rhs.severityRank
    }

    /// Maps common level strings from JSON, logfmt, syslog, JVM, Postgres, etc.
    public static func from(_ raw: String) -> LogLevel {
        let normalized = raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))

        switch normalized {
        case "error", "err", "fatal", "panic", "critical", "crit", "severe", "emerg", "alert":
            return .error
        case "warn", "warning", "notice":
            return .warn
        case "info", "informational":
            return .info
        case "debug", "dbg":
            return .debug
        case "trace", "verbose", "fine", "finer", "finest":
            return .trace
        default:
            return .unknown
        }
    }
}
