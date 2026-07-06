// ViewModels/ContainerListViewModel.swift

import Foundation
import Observation

enum ContainerStatusFilter: String, CaseIterable, Identifiable, Sendable {
    case all = "All"
    case running = "Running"
    case stopped = "Stopped"

    var id: String { rawValue }
}

enum PendingContainerAction: Equatable, Sendable, Identifiable {
    case stop(String)
    case kill(String)
    case delete(String)

    var id: String {
        switch self {
        case .stop(let containerID): "stop-\(containerID)"
        case .kill(let containerID): "kill-\(containerID)"
        case .delete(let containerID): "delete-\(containerID)"
        }
    }
}

@MainActor
@Observable
final class ContainerListViewModel {
    private(set) var containers: [ContainerSummary] = []
    private(set) var listError: WharfsideError?
    private(set) var isInitialLoading = true
    private(set) var actionInProgressIDs: Set<String> = []
    private(set) var actionBannerMessage: String?

    var searchText = ""
    var statusFilter: ContainerStatusFilter = .all
    var selectedContainerID: String?
    var pendingConfirmation: PendingContainerAction?

    private let service: any ContainerServicing
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?
    private var bannerClearTask: Task<Void, Never>?

    init(service: any ContainerServicing, pollInterval: Duration = .seconds(2)) {
        self.service = service
        self.pollInterval = pollInterval
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
        bannerClearTask?.cancel()
        bannerClearTask = nil
    }

    func refresh() async {
        do {
            let fetched = try await service.list()
            containers = Self.sorted(fetched)
            listError = nil
            isInitialLoading = false
            actionInProgressIDs.removeAll()
        } catch let mapped as WharfsideError {
            listError = mapped
            isInitialLoading = false
        } catch {
            listError = ErrorMapper.map(error)
            isInitialLoading = false
        }
    }

    func requestStart(id: String) {
        Task { await performStart(id: id) }
    }

    func requestStop(id: String) {
        pendingConfirmation = .stop(id)
    }

    func requestKill(id: String) {
        pendingConfirmation = .kill(id)
    }

    func requestDelete(id: String) {
        pendingConfirmation = .delete(id)
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    func confirm(_ action: PendingContainerAction) async {
        pendingConfirmation = nil

        switch action {
        case .stop(let id):
            await performStop(id: id)
        case .kill(let id):
            await performKill(id: id)
        case .delete(let id):
            let force = containers.first(where: { $0.id == id })?.status == .running
            await performDelete(id: id, force: force)
        }
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
        switch action {
        case .stop: return "Stop container?"
        case .kill: return "Kill container?"
        case .delete: return "Delete container?"
        }
    }

    func confirmationMessage(for action: PendingContainerAction) -> String {
        let name = containerName(for: action.containerID)
        switch action {
        case .stop:
            return "Container \(name) will receive a graceful stop signal."
        case .kill:
            return "Container \(name) will be killed immediately."
        case .delete:
            if containers.first(where: { $0.id == action.containerID })?.status == .running {
                return "Container \(name) is still running. Force delete will stop and remove it."
            }
            return "Container \(name) will be permanently removed."
        }
    }

    func destructiveConfirmationLabel(for action: PendingContainerAction) -> String {
        switch action {
        case .stop: return "Stop"
        case .kill: return "Kill"
        case .delete:
            if containers.first(where: { $0.id == action.containerID })?.status == .running {
                return "Force Delete"
            }
            return "Delete"
        }
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

    private func performStart(id: String) async {
        actionInProgressIDs.insert(id)
        do {
            try await service.start(id: id)
            showActionBanner(nil)
        } catch {
            actionInProgressIDs.remove(id)
            showActionBanner(ErrorMapper.map(error).localizedDescription)
        }
    }

    private func performStop(id: String) async {
        actionInProgressIDs.insert(id)
        do {
            try await service.stop(id: id, timeout: 10)
            showActionBanner(nil)
        } catch {
            actionInProgressIDs.remove(id)
            showActionBanner(ErrorMapper.map(error).localizedDescription)
        }
    }

    private func performKill(id: String) async {
        actionInProgressIDs.insert(id)
        do {
            try await service.kill(id: id, signal: "KILL")
            showActionBanner(nil)
        } catch {
            actionInProgressIDs.remove(id)
            showActionBanner(ErrorMapper.map(error).localizedDescription)
        }
    }

    private func performDelete(id: String, force: Bool) async {
        actionInProgressIDs.insert(id)
        do {
            try await service.delete(id: id, force: force)
            showActionBanner(nil)
        } catch {
            actionInProgressIDs.remove(id)
            showActionBanner(ErrorMapper.map(error).localizedDescription)
        }
    }

    private func containerName(for id: String) -> String {
        id
    }

    private func showActionBanner(_ message: String?) {
        bannerClearTask?.cancel()
        actionBannerMessage = message
        guard message != nil else { return }
        bannerClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.actionBannerMessage = nil
        }
    }
}

private extension PendingContainerAction {
    var containerID: String {
        switch self {
        case .stop(let id), .kill(let id), .delete(let id):
            id
        }
    }
}
