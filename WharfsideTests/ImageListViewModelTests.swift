// WharfsideTests/ImageListViewModelTests.swift

import Foundation
import Testing
@testable import Wharfside

@MainActor
struct ImageListViewModelTests {
    @Test func searchFiltersByReferenceSubstring() {
        let images = [
            ImageSummary.mock(reference: "alpine:latest"),
            ImageSummary.mock(reference: "redis:7"),
            ImageSummary.mock(reference: "nginx:1.24")
        ]

        let filtered = ImageListViewModel.filterAndSort(images: images, searchText: "redis")

        #expect(filtered.map(\.reference) == ["redis:7"])
    }

    @Test func sortingIsStableByReference() {
        let images = [
            ImageSummary.mock(reference: "zebra:latest"),
            ImageSummary.mock(reference: "alpine:latest"),
            ImageSummary.mock(reference: "beta:1")
        ]

        let sorted = ImageListViewModel.sorted(images).map(\.reference)

        #expect(sorted == ["alpine:latest", "beta:1", "zebra:latest"])
    }

    @Test func pollStopsAfterCancellation() async {
        let service = MockImageService()
        service.listDelay = .milliseconds(50)
        let viewModel = ImageListViewModel(service: service, pollInterval: .milliseconds(30))

        viewModel.startPolling()
        try? await Task.sleep(for: .milliseconds(120))
        let countAfterStart = service.listCallCount

        viewModel.stopPolling()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(service.listCallCount == countAfterStart)
    }

    @Test func deleteWaitsForConfirmation() async {
        let service = MockImageService()
        service.images = [ImageSummary.mock(reference: "alpine:latest")]
        let viewModel = ImageListViewModel(service: service)
        await viewModel.refresh()

        viewModel.requestDelete(reference: "alpine:latest")
        #expect(viewModel.actions.pendingConfirmation == .delete("alpine:latest"))
        #expect(service.deleteCallCount == 0)

        viewModel.cancelPendingAction()
        #expect(viewModel.actions.pendingConfirmation == nil)

        viewModel.requestDelete(reference: "alpine:latest")
        await viewModel.confirm(.delete("alpine:latest"))

        #expect(service.deleteCallCount == 1)
    }

    @Test func deleteFailureShowsBanner() async {
        let service = MockImageService()
        service.images = [ImageSummary.mock(reference: "busybox:latest")]
        service.deleteError = WharfsideError.invalidState("image is in use by a container")
        let viewModel = ImageListViewModel(service: service)
        await viewModel.refresh()

        viewModel.requestDelete(reference: "busybox:latest")
        await viewModel.confirm(.delete("busybox:latest"))
        try? await Task.sleep(for: .milliseconds(20))

        #expect(viewModel.bannerMessage == "image is in use by a container")
        #expect(!viewModel.actions.actionInProgressReferences.contains("busybox:latest"))
    }

    @Test func successfulDeleteRefreshesList() async {
        let service = MockImageService()
        service.images = [ImageSummary.mock(reference: "spike-test:brief")]
        let viewModel = ImageListViewModel(service: service)
        await viewModel.refresh()

        viewModel.requestDelete(reference: "spike-test:brief")
        service.images = []
        await viewModel.confirm(.delete("spike-test:brief"))

        #expect(service.deleteCallCount == 1)
        #expect(service.listCallCount >= 2)
        #expect(viewModel.images.isEmpty)
    }
}
