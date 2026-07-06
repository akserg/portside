// ViewModels/ImageListViewModel.swift

import Foundation
import Observation

@MainActor
@Observable
final class ImageListViewModel {
    private(set) var images: [ImageSummary] = []
    private(set) var listError: WharfsideError?
    private(set) var isInitialLoading = true

    var searchText = ""
    var selectedImageReference: String?

    let actions: ImageActionCoordinator
    let pulls: PullTaskCoordinator

    private let service: any ImageServicing
    private let pollInterval: Duration
    private var pollTask: Task<Void, Never>?

    init(service: any ImageServicing, pollInterval: Duration = .seconds(10)) {
        self.service = service
        self.pollInterval = pollInterval
        self.actions = ImageActionCoordinator(service: service)
        self.pulls = PullTaskCoordinator(service: service)

        self.actions.onActionSucceeded = { [weak self] in
            await self?.refresh()
        }
        self.pulls.onPullCompleted = { [weak self] in
            await self?.refresh()
        }
        self.pulls.onPullFailed = { [weak self] message in
            self?.actions.presentTransientBanner(message)
        }
    }

    var bannerMessage: String? {
        actions.actionBannerMessage ?? pulls.noticeMessage
    }

    var filteredImages: [ImageSummary] {
        Self.filterAndSort(images: images, searchText: searchText)
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
            images = Self.sorted(fetched)
            listError = nil
            isInitialLoading = false
            actions.reconcileDeletedImages(remainingReferences: Set(images.map(\.reference)))
        } catch let mapped as WharfsideError {
            listError = mapped
            isInitialLoading = false
        } catch {
            listError = ErrorMapper.map(error)
            isInitialLoading = false
        }
    }

    func requestDelete(reference: String) {
        actions.requestDelete(reference: reference)
    }

    func cancelPendingAction() {
        actions.cancelPendingAction()
    }

    func confirm(_ action: PendingImageAction) async {
        await actions.confirm(action)
    }

    func startPull(reference: String) {
        pulls.startPull(reference: reference)
    }

    func tag(source: String, target: String) async throws {
        _ = try await service.tag(source: source, target: target)
        await refresh()
    }

    func confirmationTitle(for action: PendingImageAction) -> String {
        actions.confirmationTitle(for: action)
    }

    func confirmationMessage(for action: PendingImageAction) -> String {
        actions.confirmationMessage(for: action)
    }

    func destructiveConfirmationLabel(for action: PendingImageAction) -> String {
        actions.destructiveConfirmationLabel(for: action)
    }

    nonisolated static func filterAndSort(images: [ImageSummary], searchText: String) -> [ImageSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = images.filter { image in
            guard !trimmedSearch.isEmpty else { return true }
            return image.reference.localizedCaseInsensitiveContains(trimmedSearch)
        }
        return sorted(filtered)
    }

    nonisolated static func sorted(_ images: [ImageSummary]) -> [ImageSummary] {
        images.sorted { lhs, rhs in
            let order = lhs.reference.localizedCaseInsensitiveCompare(rhs.reference)
            if order != .orderedSame { return order == .orderedAscending }
            return lhs.reference < rhs.reference
        }
    }
}
