import Foundation

/// Time window over which log entries are summarized.
public struct DigestWindow: Sendable, Equatable {
    public let description: String
    public let start: Date?
    public let end: Date?

    public init(description: String, start: Date? = nil, end: Date? = nil) {
        self.description = description
        self.start = start
        self.end = end
    }
}
