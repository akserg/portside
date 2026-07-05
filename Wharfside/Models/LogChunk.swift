// Models/LogChunk.swift

import Foundation

enum LogSource: String, Sendable, Hashable {
    case stdio
    case boot
}

struct LogChunk: Sendable, Hashable {
    let source: LogSource
    let data: Data
}
