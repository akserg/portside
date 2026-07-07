// ViewModels/ContainerListViewModel.swift

import Foundation
import Observation

enum ContainerStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case running = "Running"
    case stopped = "Stopped"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ContainerListViewModel {
    private(set) var containers: [ContainerSummary] = []
    private(set) var listError: WharfsideError?
    private(set) var isInitialLoading = true

    var searchText = ""
    var statusFilter: ContainerStatusFilter = .all
    var selectedContainerID: String?

    let actions: ContainerActionCoordinator

    private let service: any ContainerServicing
    private let lifecycleObserver: ContainerLifecycleObserver?
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    init(
        service: any ContainerServicing,
        lifecycleObserver: ContainerLifecycleObserver? = nil,
        pollInterval: Duration = .seconds(2)
    ) {
        self.service = service
        self.lifecycleObserver = lifecycleObserver
        self.pollInterval = pollInterval
        self.actions = ContainerActionCoordinator(service: service)
        self.actions.statusProvider = { [weak self] id in
            self?.containers.first(where: { $0.id == id })?.status
        }
        self.actions.onActionSucceeded = { [weak self] _ in
            await self?.refresh()
        }
    }

    var filteredContainers: [ContainerSummary] {
        Self.filterAndSort(
            containers: containers,
            searchText: searchText,
            statusFilter: statusFilter
        )
    }

    func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                await self.refresh()
                try? await Task.sleep(for: self.pollInterval)
            }
        }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        do {
            let fetched = try await service.list()
            if let lifecycleObserver {
                await lifecycleObserver.record(containers: fetched)
            }
            containers = Self.sorted(fetched)
            listError = nil
            isInitialLoading = false
            for container in containers {
                actions.reconcilePendingDisplay(containerID: container.id, actualStatus: container.status)
            }
            actions.reconcileDeletedContainers(remainingIDs: Set(containers.map(\.id)))
        } catch let mapped as WharfsideError {
            listError = mapped
            isInitialLoading = false
        } catch {
            listError = ErrorMapper.map(error)
            isInitialLoading = false
        }
    }

    func requestStart(id: String) {
        actions.requestStart(id: id)
    }

    func requestStop(id: String) {
        actions.requestStop(id: id)
    }

    func requestKill(id: String) {
        actions.requestKill(id: id)
    }

    func requestDelete(id: String) {
        actions.requestDelete(id: id)
    }

    func cancelPendingAction() {
        actions.cancelPendingAction()
    }

    func confirm(_ action: PendingContainerAction) async {
        await actions.confirm(action)
    }

    func toggleSelectedContainer() {
        guard let id = selectedContainerID,
              let container = containers.first(where: { $0.id == id }) else { return }

        switch container.status {
        case .running, .stopping:
            requestStop(id: id)
        case .stopped:
            requestStart(id: id)
        case .unknown:
            break
        }
    }

    func confirmationTitle(for action: PendingContainerAction) -> String {
        actions.confirmationTitle(for: action)
    }

    func confirmationMessage(for action: PendingContainerAction) -> String {
        actions.confirmationMessage(for: action)
    }

    func destructiveConfirmationLabel(for action: PendingContainerAction) -> String {
        actions.destructiveConfirmationLabel(for: action)
    }

    func listStatusSummary(for container: ContainerSummary) -> String {
        actions.listStatusSummary(for: container)
    }

    nonisolated static func filterAndSort(
        containers: [ContainerSummary],
        searchText: String,
        statusFilter: ContainerStatusFilter
    ) -> [ContainerSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = containers.filter { container in
            switch statusFilter {
            case .all:
                true
            case .running:
                container.status == .running || container.status == .stopping
            case .stopped:
                container.status == .stopped || container.status == .unknown
            }
        }.filter { container in
            guard !trimmedSearch.isEmpty else { return true }
            return container.id.localizedCaseInsensitiveContains(trimmedSearch)
                || container.image.localizedCaseInsensitiveContains(trimmedSearch)
        }
        return sorted(filtered)
    }

    nonisolated static func sorted(_ containers: [ContainerSummary]) -> [ContainerSummary] {
        containers.sorted { lhs, rhs in
            let lhsPriority = statusSortPriority(lhs.status)
            let rhsPriority = statusSortPriority(rhs.status)
            if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
            let nameOrder = lhs.id.localizedCaseInsensitiveCompare(rhs.id)
            if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
            return lhs.id < rhs.id
        }
    }

    nonisolated private static func statusSortPriority(_ status: ContainerRuntimeStatus) -> Int {
        switch status {
        case .running: 0
        case .stopping: 1
        case .unknown: 2
        case .stopped: 3
        }
    }
}
