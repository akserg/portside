import Foundation

/// A single parsed log line (or merged multi-line entry such as a JVM stack trace).
public struct LogEntry: Sendable, Equatable {
    public let timestamp: Date?
    public let level: LogLevel
    public let message: String
    public let raw: String

    public init(timestamp: Date?, level: LogLevel, message: String, raw: String) {
        self.timestamp = timestamp
        self.level = level
        self.message = message
        self.raw = raw
    }
}
