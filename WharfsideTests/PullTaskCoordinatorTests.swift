// WharfsideTests/PullTaskCoordinatorTests.swift

import Foundation
import Testing
@testable import Wharfside

@MainActor
struct PullTaskCoordinatorTests {
    @Test func pullUpdatesProgressAndRefreshesOnCompletion() async {
        let service = MockImageService()
        service.pullDelay = .milliseconds(30)
        let coordinator = PullTaskCoordinator(service: service)
        var refreshCount = 0
        coordinator.onPullCompleted = {
            refreshCount += 1
        }

        coordinator.startPull(reference: "alpine:latest")
        #expect(coordinator.activePulls.count == 1)
        #expect(await TestPolling.waitUntil { coordinator.activePulls.isEmpty })

        #expect(service.pullCallCount == 1)
        #expect(refreshCount == 1)
    }

    @Test func pullFailureSurfacesBannerAndRecordsInSheet() async {
        let service = MockImageService()
        service.pullError = WharfsideError.notFound("manifest unknown")
        let coordinator = PullTaskCoordinator(service: service)
        var bannerMessage: String?
        coordinator.onPullFailed = { bannerMessage = $0 }

        coordinator.startPull(reference: "bogus:missing")
        #expect(await TestPolling.waitUntil { coordinator.activePulls.isEmpty })

        #expect(bannerMessage == "manifest unknown")
        #expect(coordinator.recentFailures.count == 1)
        #expect(coordinator.recentFailures.first?.reference == "bogus:missing")
    }

    @Test func concurrentPullsAreAllowed() async {
        let service = MockImageService()
        service.pullDelay = .milliseconds(50)
        let coordinator = PullTaskCoordinator(service: service)

        coordinator.startPull(reference: "alpine:latest")
        coordinator.startPull(reference: "redis:7")
        #expect(coordinator.activePulls.count == 2)

        #expect(await TestPolling.waitUntil {
            service.pullCallCount == 2 && coordinator.activePulls.isEmpty
        })
    }

    @Test func duplicatePullShowsNoticeWithoutSecondTask() async {
        let service = MockImageService()
        let pullStarted = PullGate()
        service.pullHandler = { _, _ in
            await pullStarted.markStarted()
            try await Task.sleep(for: .seconds(30))
            return ImageSummary.mock(reference: "alpine:latest")
        }

        let coordinator = PullTaskCoordinator(service: service)

        coordinator.startPull(reference: "alpine:latest")
        await pullStarted.waitUntilStarted()
        coordinator.startPull(reference: "alpine:latest")

        #expect(coordinator.activePulls.count == 1)
        #expect(coordinator.noticeMessage == "Already pulling alpine:latest")
        #expect(service.pullCallCount == 1)
    }

    @Test func progressCallbackUpdatesActivePull() async {
        let service = MockImageService()
        // Hold the mock pull open after the first progress event so MainActor can
        // apply it to activePulls before the stream finishes (CI was racing past
        // "layer 1" into completion in one turn).
        let releaseAfterFirstProgress = PullGate()
        service.pullHandler = { _, onProgress in
            onProgress?(PullProgress(description: "layer 1", completedUnits: 1, totalUnits: 3))
            await releaseAfterFirstProgress.waitUntilStarted()
            onProgress?(PullProgress(description: "layer 2", completedUnits: 2, totalUnits: 3))
            return ImageSummary.mock(reference: "alpine:latest")
        }

        let coordinator = PullTaskCoordinator(service: service)
        coordinator.startPull(reference: "alpine:latest")
        #expect(await TestPolling.waitUntil {
            coordinator.activePulls.first?.progress?.description == "layer 1"
        })
        await releaseAfterFirstProgress.markStarted()

        #expect(await TestPolling.waitUntil { coordinator.activePulls.isEmpty })
    }
}

private actor PullGate {
    private var started = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func markStarted() {
        started = true
        for waiter in waiters {
            waiter.resume()
        }
        waiters.removeAll()
    }

    func waitUntilStarted() async {
        if started { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}
