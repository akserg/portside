import Foundation
@testable import WharfsideAnalysis

enum BootFixtureEntries {
    /// Loads an unlabeled boot-log fixture as `.boot` entries (mirrors runtime log collection).
    static func loadBootLog(named filename: String) throws -> [LogEntry] {
        let text = try FixtureLoader.loadLog(named: filename)
        return LogParser().parse(text: text).map {
            LogEntry(
                timestamp: $0.timestamp,
                level: $0.level,
                message: $0.message,
                raw: $0.raw,
                source: .boot
            )
        }
    }
}
