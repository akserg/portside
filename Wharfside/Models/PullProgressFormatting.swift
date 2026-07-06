// Models/PullProgressFormatting.swift

import Foundation

enum PullProgressFormatting {
    static func elapsed(since start: Date, now: Date = .now) -> String {
        ContainerSummaryFormatting.formatDuration(now.timeIntervalSince(start))
    }

    static func statusLabel(progress: PullProgress?, startedAt: Date, now: Date = .now) -> String {
        let elapsed = elapsed(since: startedAt, now: now)
        let detail = progressDetail(progress)
        if detail.isEmpty {
            return "Pulling · \(elapsed)"
        }
        return "\(detail) · \(elapsed)"
    }

    static func progressDetail(_ progress: PullProgress?) -> String {
        guard let progress else { return "Starting…" }
        if let total = progress.totalUnits, total > 0 {
            return "\(progress.description) (\(progress.completedUnits)/\(total))"
        }
        if progress.completedUnits > 0 {
            return "\(progress.description) (\(progress.completedUnits) layers)"
        }
        return progress.description
    }

    static func progressFraction(_ progress: PullProgress?) -> Double? {
        guard let progress, let total = progress.totalUnits, total > 0 else { return nil }
        return min(1, max(0, Double(progress.completedUnits) / Double(total)))
    }
}
