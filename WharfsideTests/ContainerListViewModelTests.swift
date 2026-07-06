// WharfsideTests/ContainerListViewModelTests.swift

import Foundation
import Testing
@testable import Wharfside

@MainActor
struct ContainerListViewModelTests {
    @Test func combinedSearchAndStatusFilter() {
        let containers = [
            ContainerSummary.mock(id: "api", image: "nginx:latest", status: .running),
            ContainerSummary.mock(id: "db", image: "postgres:16", status: .stopped),
            ContainerSummary.mock(id: "cache", image: "redis:7", status: .running)
        ]

        let filtered = ContainerListViewModel.filterAndSort(
            containers: containers,
            searchText: "ng",
            statusFilter: .running
        )

        #expect(filtered.map(\.id) == ["api"])
    }

    @Test func sortingKeepsRunningContainersFirstAndStableByName() {
        let firstPoll = [
            ContainerSummary.mock(id: "zebra", image: "alpine", status: .stopped),
            ContainerSummary.mock(id: "alpha", image: "alpine", status: .running),
            ContainerSummary.mock(id: "beta", image: "alpine", status: .running)
        ]
        let secondPoll = [
            ContainerSummary.mock(id: "zebra", image: "alpine", status: .stopped),
            ContainerSummary.mock(id: "beta", image: "alpine", status: .running),
            ContainerSummary.mock(id: "alpha", image: "alpine", status: .running)
        ]

        let firstOrder = ContainerListViewModel.sorted(firstPoll).map(\.id)
        let secondOrder = ContainerListViewModel.sorted(secondPoll).map(\.id)

        #expect(firstOrder == ["alpha", "beta", "zebra"])
        #expect(secondOrder == firstOrder)
    }

    @Test func pollStopsAfterCancellation() async {
        let service = MockContainerService()
        service.listDelay = .milliseconds(50)
        let viewModel = ContainerListViewModel(service: service, pollInterval: .milliseconds(30))

        viewModel.startPolling()
        try? await Task.sleep(for: .milliseconds(120))
        let countAfterStart = service.listCallCount

        viewModel.stopPolling()
        try? await Task.sleep(for: .milliseconds(120))

        #expect(service.listCallCount == countAfterStart)
    }

    @Test func listErrorRecoversOnSuccessfulPoll() async {
        let service = MockContainerService()
        service.listError = WharfsideError.serviceNotRunning
        let viewModel = ContainerListViewModel(service: service)

        await viewModel.refresh()
        #expect(viewModel.listError == .serviceNotRunning)

        service.listError = nil
        service.summaries = [ContainerSummary.mock(id: "hello", image: "alpine", status: .running)]
        await viewModel.refresh()

        #expect(viewModel.listError == nil)
        #expect(viewModel.containers.map(\.id) == ["hello"])
    }

    @Test func optimisticActionClearsSpinnerOnSuccessfulPoll() async {
        let service = MockContainerService()
        service.summaries = [ContainerSummary.mock(id: "app", image: "alpine", status: .stopped)]
        let viewModel = ContainerListViewModel(service: service)

        await viewModel.refresh()
        viewModel.requestStart(id: "app")
        try? await Task.sleep(for: .milliseconds(20))

        #expect(viewModel.actionInProgressIDs.contains("app"))

        await viewModel.refresh()
        #expect(viewModel.actionInProgressIDs.isEmpty)
        #expect(service.startCallCount == 1)
    }

    @Test func destructiveActionWaitsForConfirmation() async {
        let service = MockContainerService()
        service.summaries = [ContainerSummary.mock(id: "app", image: "alpine", status: .running)]
        let viewModel = ContainerListViewModel(service: service)
        await viewModel.refresh()

        viewModel.requestStop(id: "app")
        #expect(viewModel.pendingConfirmation == .stop("app"))
        #expect(service.stopCallCount == 0)

        viewModel.cancelPendingAction()
        #expect(viewModel.pendingConfirmation == nil)
        #expect(service.stopCallCount == 0)

        viewModel.requestDelete(id: "app")
        await viewModel.confirm(.delete("app"))

        #expect(service.deleteCallCount == 1)
        #expect(service.lastDeleteForce == true)
    }

    @Test func confirmRunsWithCapturedActionAfterPendingCleared() async {
        let service = MockContainerService()
        service.summaries = [ContainerSummary.mock(id: "app", image: "alpine", status: .running)]
        let viewModel = ContainerListViewModel(service: service)
        await viewModel.refresh()

        viewModel.pendingConfirmation = nil
        await viewModel.confirm(.stop("app"))

        #expect(service.stopCallCount == 1)
    }

    @Test func deleteStoppedContainerUsesNonForceDelete() async {
        let service = MockContainerService()
        service.summaries = [ContainerSummary.mock(id: "app", image: "alpine", status: .stopped)]
        let viewModel = ContainerListViewModel(service: service)
        await viewModel.refresh()

        viewModel.requestDelete(id: "app")
        await viewModel.confirm(.delete("app"))

        #expect(service.deleteCallCount == 1)
        #expect(service.lastDeleteForce == false)
    }

    @Test func actionFailureShowsBannerAndClearsSpinner() async {
        let service = MockContainerService()
        service.summaries = [ContainerSummary.mock(id: "app", image: "alpine", status: .stopped)]
        service.startError = WharfsideError.invalidState("container is already running")
        let viewModel = ContainerListViewModel(service: service)

        viewModel.requestStart(id: "app")
        try? await Task.sleep(for: .milliseconds(20))

        #expect(viewModel.actionBannerMessage == "container is already running")
        #expect(!viewModel.actionInProgressIDs.contains("app"))
    }
}
