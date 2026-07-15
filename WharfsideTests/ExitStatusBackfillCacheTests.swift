// WharfsideTests/ExitStatusBackfillCacheTests.swift
// B6 — Overview exit-code backfill from diagnosis.

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
struct ExitStatusBackfillCacheTests {
    @Test func runtimeKnownWinsOverCache() {
        let cache = ExitStatusBackfillCache()
        cache.record(
            containerID: "hello",
            status: .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        let resolved = cache.overviewStatus(
            runtime: .known(1, source: .runtime),
            containerID: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(resolved == .known(1, source: .runtime))
    }

    @Test func cacheFillsWhenRuntimeUnavailable() {
        let cache = ExitStatusBackfillCache()
        cache.record(
            containerID: "hello",
            status: .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        let resolved = cache.overviewStatus(
            runtime: .unavailable(reason: .runtimeGone),
            containerID: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 50)
        )

        #expect(resolved == .known(137, source: .bootLog))
    }

    @Test func runningInvalidatesCache() {
        let cache = ExitStatusBackfillCache()
        cache.record(
            containerID: "hello",
            status: .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        let whileRunning = cache.overviewStatus(
            runtime: .unavailable(reason: .stillRunning),
            containerID: "hello",
            status: .running,
            startedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(whileRunning == .unavailable(reason: .stillRunning))

        let afterStop = cache.overviewStatus(
            runtime: .unavailable(reason: .runtimeGone),
            containerID: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 200)
        )
        #expect(afterStop == .unavailable(reason: .runtimeGone))
    }

    @Test func startedAtAfterDiagnosisInvalidatesCache() {
        let cache = ExitStatusBackfillCache()
        cache.record(
            containerID: "hello",
            status: .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        let resolved = cache.overviewStatus(
            runtime: .unavailable(reason: .noEvidence),
            containerID: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 150)
        )

        #expect(resolved == .unavailable(reason: .noEvidence))
    }
}

@MainActor
struct ContainerDetailExitStatusBackfillTests {
    @Test func diagnosisBackfillExposesBootLogOnOverview() async {
        let service = MockContainerService()
        service.detailsByID["hello"] = .mock(
            id: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 50),
            exitStatus: .unavailable(reason: .runtimeGone)
        )
        let cache = ExitStatusBackfillCache()
        let viewModel = ContainerDetailViewModel(
            containerID: "hello",
            service: service,
            exitStatusBackfill: cache
        )

        await viewModel.refresh()
        #expect(viewModel.overviewExitStatus == .unavailable(reason: .runtimeGone))
        #expect(viewModel.overviewExitStatus.overviewDisplay == nil)

        viewModel.recordDiagnosisExitStatus(
            .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(viewModel.overviewExitStatus == .known(137, source: .bootLog))
        #expect(viewModel.overviewExitStatus.overviewDisplay == "137 (boot log)")
        #expect(service.logStreamCallCount == 0)
    }

    @Test func restartClearsBackfill() async {
        let service = MockContainerService()
        service.detailsByID["hello"] = .mock(
            id: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 50),
            exitStatus: .unavailable(reason: .runtimeGone)
        )
        let cache = ExitStatusBackfillCache()
        let viewModel = ContainerDetailViewModel(
            containerID: "hello",
            service: service,
            exitStatusBackfill: cache
        )

        await viewModel.refresh()
        viewModel.recordDiagnosisExitStatus(
            .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )
        #expect(viewModel.overviewExitStatus == .known(137, source: .bootLog))

        service.detailsByID["hello"] = .mock(
            id: "hello",
            status: .running,
            startedAt: Date(timeIntervalSince1970: 200),
            exitStatus: .unavailable(reason: .stillRunning)
        )
        await viewModel.refresh()
        #expect(viewModel.overviewExitStatus == .unavailable(reason: .stillRunning))
        #expect(viewModel.overviewExitStatus.overviewDisplay == nil)

        service.detailsByID["hello"] = .mock(
            id: "hello",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 200),
            exitStatus: .unavailable(reason: .runtimeGone)
        )
        await viewModel.refresh()
        #expect(viewModel.overviewExitStatus == .unavailable(reason: .runtimeGone))
    }

    @Test func runtimeKnownStillWinsAfterBackfill() async {
        let service = MockContainerService()
        service.detailsByID["crashy"] = .mock(
            id: "crashy",
            status: .stopped,
            startedAt: Date(timeIntervalSince1970: 50),
            exitStatus: .known(1, source: .runtime)
        )
        let viewModel = ContainerDetailViewModel(containerID: "crashy", service: service)

        await viewModel.refresh()
        viewModel.recordDiagnosisExitStatus(
            .known(137, source: .bootLog),
            diagnosedAt: Date(timeIntervalSince1970: 100)
        )

        #expect(viewModel.overviewExitStatus == .known(1, source: .runtime))
        #expect(viewModel.overviewExitStatus.overviewDisplay == "1")
    }
}
