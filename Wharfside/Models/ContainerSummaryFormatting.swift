// Models/ContainerSummaryFormatting.swift

import Foundation

enum ContainerSummaryFormatting {
    static func uptimeOrExitSummary(status: ContainerRuntimeStatus, startedAt: Date?, now: Date = .now) -> String {
        switch status {
        case .running:
            guard let startedAt else { return "Running" }
            return formatDuration(now.timeIntervalSince(startedAt))
        case .stopping:
            return "Stopping…"
        case .stopped:
            return "Stopped"
        case .unknown:
            return "Unknown"
        }
    }

    static func formatDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            return "\(days)d \(hours)h"
        }
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return "\(minutes)m"
        }
        return "\(totalSeconds)s"
    }
}
