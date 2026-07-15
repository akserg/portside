// ViewModels/ExitStatusBackfillCache.swift
// B6 — session-scoped Overview exit-code backfill from diagnosis (no extra log fetch).

import Foundation
import Observation
import WharfsideAnalysis

/// In-memory exit status resolved during diagnosis, used as an Overview fallback when
/// runtime XPC has no known code. Dies with the process; never invokes the boot-log parser.
@MainActor
@Observable
final class ExitStatusBackfillCache {
    private struct Entry: Sendable, Equatable {
        let status: ExitStatus
        let diagnosedAt: Date
    }

    private var entries: [String: Entry] = [:]

    func record(containerID: String, status: ExitStatus, diagnosedAt: Date = .now) {
        entries[containerID] = Entry(status: status, diagnosedAt: diagnosedAt)
    }

    func invalidate(containerID: String) {
        entries.removeValue(forKey: containerID)
    }

    /// Clears a cached value when the container is running again.
    func invalidateIfRunning(containerID: String, status: ContainerRuntimeStatus) {
        if status == .running {
            invalidate(containerID: containerID)
        }
    }

    /// Precedence: live runtime `.known` > valid diagnosis cache > runtime (usually `—`).
    /// Stale-guard: `startedAt` after `diagnosedAt` drops the cache even if a running
    /// transition was missed.
    func overviewStatus(
        runtime: ExitStatus,
        containerID: String,
        status: ContainerRuntimeStatus,
        startedAt: Date?
    ) -> ExitStatus {
        invalidateIfRunning(containerID: containerID, status: status)

        if case .known = runtime {
            return runtime
        }

        guard let entry = entries[containerID] else {
            return runtime
        }

        if let startedAt, startedAt > entry.diagnosedAt {
            invalidate(containerID: containerID)
            return runtime
        }

        return entry.status
    }
}
