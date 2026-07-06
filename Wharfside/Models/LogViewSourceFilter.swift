// Models/LogViewSourceFilter.swift

import Foundation

enum LogViewSourceFilter: String, CaseIterable, Identifiable, Sendable {
    case stdio
    case boot
    case both

    var id: String { rawValue }

    var logSource: LogSource? {
        switch self {
        case .stdio: .stdio
        case .boot: .boot
        case .both: nil
        }
    }

    func includes(_ source: LogSource) -> Bool {
        switch self {
        case .stdio: source == .stdio
        case .boot: source == .boot
        case .both: true
        }
    }
}
