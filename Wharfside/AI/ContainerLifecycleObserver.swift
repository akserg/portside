// AI/ContainerLifecycleObserver.swift
// Issue 1.6 — app-derived restart counts from list polling (apple/container 1.0 has no field).

import Foundation

/// Best-effort restart counter derived from container list polling.
///
/// Counts observed running→stopped→running transitions per container ID. Resets on app
/// launch; not persisted. Feed via `record(containers:)` on each list refresh.
actor ContainerLifecycleObserver {
    private enum Phase: Sendable {
        case unknown
        case running
        case stoppedAfterRunning
        case idleStopped
    }

    private var phases: [String: Phase] = [:]
    private var restartCounts: [String: Int] = [:]

    func record(containers: [ContainerSummary]) {
        for container in containers {
            observe(id: container.id, status: container.status)
        }
    }

    func restartCount(for containerID: String) -> Int {
        restartCounts[containerID, default: 0]
    }

    private func observe(id: String, status: ContainerRuntimeStatus) {
        let previous = phases[id, default: .unknown]

        if Self.isRunningLike(status) {
            if previous == .stoppedAfterRunning {
                restartCounts[id, default: 0] += 1
            }
            phases[id] = .running
            return
        }

        if status == .stopped {
            switch previous {
            case .running:
                phases[id] = .stoppedAfterRunning
            case .unknown:
                phases[id] = .idleStopped
            case .stoppedAfterRunning, .idleStopped:
                break
            }
            return
        }

        if previous == .running {
            phases[id] = .stoppedAfterRunning
        }
    }

    private static func isRunningLike(_ status: ContainerRuntimeStatus) -> Bool {
        status == .running || status == .stopping
    }
}
