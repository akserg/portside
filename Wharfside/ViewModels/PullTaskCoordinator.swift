// ViewModels/PullTaskCoordinator.swift

import Foundation
import Observation

@MainActor
@Observable
final class PullTaskCoordinator {
    struct ActivePull: Identifiable, Equatable {
        let id: UUID
        let reference: String
        let startedAt: Date
        var progress: PullProgress?
    }

    struct PullFailure: Identifiable, Equatable {
        let id: UUID
        let reference: String
        let message: String
        let occurredAt: Date
    }

    private(set) var activePulls: [ActivePull] = []
    private(set) var noticeMessage: String?
    private(set) var recentFailures: [PullFailure] = []

    var onPullFailed: ((String) -> Void)?
    var onPullCompleted: (() async -> Void)?

    private let service: any ImageServicing
    private var inFlightReferences: Set<String> = []
    private var pullTasks: [String: Task<Void, Never>] = [:]
    private var noticeClearTask: Task<Void, Never>?

    init(service: any ImageServicing) {
        self.service = service
    }

    func isPulling(reference: String) -> Bool {
        inFlightReferences.contains(reference)
    }

    func dismissFailure(id: UUID) {
        recentFailures.removeAll { $0.id == id }
    }

    func startPull(reference: String) {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if inFlightReferences.contains(trimmed) {
            presentNotice("Already pulling \(trimmed)")
            return
        }

        let pull = ActivePull(id: UUID(), reference: trimmed, startedAt: .now)
        activePulls.append(pull)
        inFlightReferences.insert(trimmed)

        pullTasks[trimmed] = Task { [weak self] in
            await self?.executePull(reference: trimmed, pullID: pull.id)
        }
    }

    private func executePull(reference: String, pullID: UUID) async {
        defer {
            inFlightReferences.remove(reference)
            pullTasks.removeValue(forKey: reference)
        }

        do {
            let (stream, continuation) = AsyncStream<PullProgress>.makeStream()

            try await withThrowingTaskGroup(of: Void.self) { group in
                group.addTask {
                    defer { continuation.finish() }
                    _ = try await self.service.pull(reference: reference) { progress in
                        continuation.yield(progress)
                    }
                }

                for await progress in stream {
                    updateProgress(pullID: pullID, progress: progress)
                }

                try await group.waitForAll()
            }

            removePull(pullID: pullID)
            await onPullCompleted?()
        } catch {
            let message = ErrorMapper.map(error).localizedDescription
            recordFailure(reference: reference, message: message)
            removePull(pullID: pullID)
            onPullFailed?(message)
        }
    }

    private func updateProgress(pullID: UUID, progress: PullProgress) {
        guard let index = activePulls.firstIndex(where: { $0.id == pullID }) else { return }
        activePulls[index].progress = progress
    }

    private func removePull(pullID: UUID) {
        activePulls.removeAll { $0.id == pullID }
    }

    private func recordFailure(reference: String, message: String) {
        recentFailures.insert(
            PullFailure(id: UUID(), reference: reference, message: message, occurredAt: .now),
            at: 0
        )
        if recentFailures.count > 5 {
            recentFailures.removeLast(recentFailures.count - 5)
        }
    }

    private func presentNotice(_ message: String) {
        noticeClearTask?.cancel()
        noticeMessage = message
        noticeClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.noticeMessage = nil
        }
    }
}
