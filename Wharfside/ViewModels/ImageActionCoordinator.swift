// ViewModels/ImageActionCoordinator.swift

import Foundation
import Observation

@MainActor
@Observable
final class ImageActionCoordinator {
    private(set) var actionInProgressReferences: Set<String> = []
    private(set) var actionBannerMessage: String?

    var pendingConfirmation: PendingImageAction?
    var onActionSucceeded: (@Sendable () async -> Void)?

    private let service: any ImageServicing
    private var bannerClearTask: Task<Void, Never>?

    init(service: any ImageServicing) {
        self.service = service
    }

    func requestDelete(reference: String) {
        pendingConfirmation = .delete(reference)
    }

    func cancelPendingAction() {
        pendingConfirmation = nil
    }

    func confirm(_ action: PendingImageAction) async {
        pendingConfirmation = nil

        switch action {
        case .delete(let reference):
            await performDelete(reference: reference)
        }
    }

    func confirmationTitle(for action: PendingImageAction) -> String {
        ImageActionSupport.confirmationTitle(for: action)
    }

    func confirmationMessage(for action: PendingImageAction) -> String {
        ImageActionSupport.confirmationMessage(for: action)
    }

    func destructiveConfirmationLabel(for action: PendingImageAction) -> String {
        ImageActionSupport.destructiveConfirmationLabel(for: action)
    }

    func presentTransientBanner(_ message: String) {
        showActionBanner(message)
    }

    private func performDelete(reference: String) async {
        actionInProgressReferences.insert(reference)
        do {
            try await service.delete(reference: reference)
            showActionBanner(nil)
            await onActionSucceeded?()
        } catch {
            actionInProgressReferences.remove(reference)
            showActionBanner(ErrorMapper.map(error).localizedDescription)
        }
    }

    func reconcileDeletedImages(remainingReferences: Set<String>) {
        for reference in actionInProgressReferences where !remainingReferences.contains(reference) {
            actionInProgressReferences.remove(reference)
        }
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
