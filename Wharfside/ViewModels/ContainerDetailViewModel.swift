// ViewModels/ContainerDetailViewModel.swift

import Foundation
import Observation
import WharfsideAnalysis

enum ContainerDetailTab: String, CaseIterable, Identifiable, Sendable {
    case overview = "Overview"
    case ports = "Ports"
    case mounts = "Mounts"
    case environment = "Environment"
    case networks = "Networks"
    case logs = "Logs"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ContainerDetailViewModel {
    let containerID: String

    private(set) var detail: ContainerDetail?
    private(set) var isInitialLoading = true
    private(set) var isGone = false
    private(set) var revealedEnvironmentKeys: Set<String> = []
    /// Overview Exit code field — runtime first, then diagnosis backfill (B6).
    private(set) var overviewExitStatus: ExitStatus = .unavailable(reason: .noEvidence)

    var selectedTab: ContainerDetailTab = .overview

    let actions: ContainerActionCoordinator

    private let service: any ContainerServicing
    private let exitStatusBackfill: ExitStatusBackfillCache
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    init(
        containerID: String,
        service: any ContainerServicing,
        exitStatusBackfill: ExitStatusBackfillCache? = nil,
        pollInterval: Duration = .seconds(5)
    ) {
        self.containerID = containerID
        self.service = service
        self.exitStatusBackfill = exitStatusBackfill ?? ExitStatusBackfillCache()
        self.pollInterval = pollInterval
        self.actions = ContainerActionCoordinator(service: service)
        self.actions.statusProvider = { [weak self] id in
            guard let self, id == self.containerID else { return nil }
            return self.detail?.status
        }
        self.actions.onActionSucceeded = { [weak self] id in
            guard let self, id == self.containerID else { return }
            await self.refresh()
        }
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            await self.refresh()
            while !Task.isCancelled {
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                await self.refresh()
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let fetched = try await service.get(id: containerID)
            detail = fetched
            isGone = false
            isInitialLoading = false
            actions.reconcilePendingDisplay(containerID: containerID, actualStatus: fetched.status)
            syncOverviewExitStatus()
        } catch let error as WharfsideError {
            if case .notFound = error {
                detail = nil
                isGone = true
                isInitialLoading = false
                overviewExitStatus = .unavailable(reason: .noEvidence)
                actions.clearPending(for: containerID)
            } else {
                actions.presentTransientBanner(error.localizedDescription)
                isInitialLoading = false
            }
        } catch {
            actions.presentTransientBanner(ErrorMapper.map(error).localizedDescription)
            isInitialLoading = false
        }
    }

    /// Called when diagnosis completes so Overview can show boot-log / resolved exit codes.
    func recordDiagnosisExitStatus(_ status: ExitStatus, diagnosedAt: Date = .now) {
        exitStatusBackfill.record(
            containerID: containerID,
            status: status,
            diagnosedAt: diagnosedAt
        )
        syncOverviewExitStatus()
    }

    func isEnvironmentValueRevealed(key: String) -> Bool {
        revealedEnvironmentKeys.contains(key)
    }

    func toggleEnvironmentReveal(key: String) {
        if revealedEnvironmentKeys.contains(key) {
            revealedEnvironmentKeys.remove(key)
        } else {
            revealedEnvironmentKeys.insert(key)
        }
    }

    func environmentValue(for variable: ContainerEnvironmentVariable) -> String {
        variable.value
    }

    func maskedEnvironmentValue(for variable: ContainerEnvironmentVariable) -> String {
        guard !variable.value.isEmpty else { return "" }
        return String(repeating: "•", count: min(variable.value.count, 8))
    }

    func displayStatusLabel(for detail: ContainerDetail) -> String {
        actions.displayStatusLabel(for: detail.id, actual: detail.status)
    }

    private func syncOverviewExitStatus() {
        guard let detail else {
            overviewExitStatus = .unavailable(reason: .noEvidence)
            return
        }
        overviewExitStatus = exitStatusBackfill.overviewStatus(
            runtime: detail.exitStatus,
            containerID: containerID,
            status: detail.status,
            startedAt: detail.startedAt
        )
    }
}
