// WharfsideTests/DiagnosisCardViewModelTests.swift
// Issue 1.7 — diagnosis card state machine (mocked service).

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
struct DiagnosisCardViewModelTests {
    @Test func eligibleWhenStopped() async {
        let viewModel = makeViewModel()
        viewModel.updateContainer(stoppedContainer(id: "app"))
        viewModel.updateObserverRestartCount(0)
        #expect(viewModel.isEligible)
    }

    @Test func eligibleWhenRestartCountPositive() async {
        let viewModel = makeViewModel()
        viewModel.updateContainer(runningContainer(id: "app"))
        viewModel.updateObserverRestartCount(2)
        #expect(viewModel.isEligible)
    }

    @Test func notEligibleWhenRunningWithZeroRestarts() async {
        let viewModel = makeViewModel()
        viewModel.updateContainer(runningContainer(id: "app"))
        viewModel.updateObserverRestartCount(0)
        #expect(!viewModel.isEligible)
    }

    @Test func idleToRunningToResult() async throws {
        let session = StubDiagnosisSession(mode: .emit(cardSampleDiagnosis))
        let viewModel = makeViewModel(session: session)
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(viewModel.isRunning)

        #expect(await TestPolling.waitUntil {
            if case .result = viewModel.phase { return true }
            return false
        })

        if case .result(let state) = viewModel.phase {
            #expect(state.result.diagnosis.summary == cardSampleDiagnosis.summary)
            #expect(!state.result.wasDegraded)
        } else {
            Issue.record("Expected result phase")
        }
    }

    @Test func degradedResultPreservesFlag() async throws {
        let violating = ContainerDiagnosis(
            summary: "Unknown failure.",
            category: .unknown,
            suggestedActions: ["Inspect logs"],
            confidence: .high
        )
        let session = StubDiagnosisSession(mode: .emitSequence([violating, violating]))
        let viewModel = makeViewModel(session: session)
        viewModel.logEntriesProvider = { cardSampleEntries() }
        viewModel.updateContainer(stoppedContainer(id: "db"))

        viewModel.explain()
        #expect(await TestPolling.waitUntil {
            if case .result = viewModel.phase { return true }
            return false
        })

        if case .result(let state) = viewModel.phase {
            #expect(state.result.wasDegraded)
        } else {
            Issue.record("Expected degraded result")
        }
    }

    @Test func failedPathSurfacesRetryMessage() async throws {
        let session = ThrowingDiagnosisSession(error: .timedOut)
        let viewModel = makeViewModel(session: session)
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(await TestPolling.waitUntil {
            if case .failed = viewModel.phase { return true }
            return false
        })

        if case .failed(let message) = viewModel.phase {
            #expect(message.contains("timed out"))
        } else {
            Issue.record("Expected failed phase")
        }
    }

    @Test func cancellationOnContainerSwitchReturnsIdle() async throws {
        let session = StubDiagnosisSession(mode: .delayedEmit(cardSampleDiagnosis, delay: .milliseconds(200)))
        let viewModel = makeViewModel(session: session)
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(viewModel.isRunning)

        viewModel.updateContainer(stoppedContainer(id: "other"))
        try await Task.sleep(for: .milliseconds(80))

        #expect(viewModel.phase == .idle)
    }

    @Test func regenerateReplacesResultWithRunningState() async throws {
        let first = ContainerDiagnosis(
            summary: "First opinion",
            category: .configuration,
            suggestedActions: ["Inspect logs"],
            confidence: .high
        )
        let second = ContainerDiagnosis(
            summary: "Second opinion",
            category: .configuration,
            suggestedActions: ["Free disk space"],
            confidence: .medium
        )
        let session = StubDiagnosisSession(mode: .emitSequence([first, second]))
        let viewModel = makeViewModel(session: session)
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(await TestPolling.waitUntil {
            if case .result = viewModel.phase { return true }
            return false
        })

        viewModel.regenerate()
        if case .running = viewModel.phase {
            // Single in-place panel — no stacked previous result.
        } else {
            Issue.record("Expected running after regenerate")
        }

        #expect(await TestPolling.waitUntil {
            if case .result(let state) = viewModel.phase {
                return state.result.diagnosis.summary == "Second opinion"
            }
            return false
        })
    }

    @Test func usesBufferedEntriesBeforeColdFetch() async throws {
        let session = CapturingDiagnosisSession()
        let viewModel = makeViewModel(session: session)
        viewModel.logEntriesProvider = { cardSampleEntries() }
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(await TestPolling.waitUntil {
            if case .result = viewModel.phase { return true }
            return false
        })

        #expect(session.lastPrompt?.contains("connection refused") == true)
    }

    @Test func aiUnavailableReturnsToIdle() async throws {
        let viewModel = makeViewModel(
            availability: StubProvider(sequence: [.heuristicsOnly(.appleIntelligenceNotEnabled)])
        )
        viewModel.updateContainer(stoppedContainer(id: "app"))

        viewModel.explain()
        #expect(await TestPolling.waitUntil { viewModel.phase == .idle })
    }

    // MARK: - Helpers

    private func makeViewModel(
        session: any DiagnosisSessioning = StubDiagnosisSession(mode: .emit(cardSampleDiagnosis)),
        availability: StubProvider = StubProvider(sequence: [.full])
    ) -> DiagnosisCardViewModel {
        let service = LogDiagnosisService(
            availability: availability,
            lifecycleObserver: ContainerLifecycleObserver(),
            sessionFactory: session
        )
        let containerService = MockContainerService()
        return DiagnosisCardViewModel(
            containerID: "app",
            diagnosisService: service,
            containerService: containerService,
            logEntriesProvider: { cardSampleEntries() }
        )
    }
}

private let cardSampleDiagnosis = ContainerDiagnosis(
    summary: "Connection refused to database.",
    category: .dependencyUnreachable,
    suggestedActions: ["Check database host"],
    confidence: .high
)

private func cardSampleEntries() -> [LogEntry] {
    [
        LogEntry(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            level: .error,
            message: "connection refused",
            raw: "ERROR: connection refused"
        )
    ]
}

private final class ThrowingDiagnosisSession: DiagnosisSessioning, @unchecked Sendable {
    let error: DiagnosisError

    init(error: DiagnosisError) {
        self.error = error
    }

    func prewarm(instructions: String) async throws {}

    func stream(
        instructions: String,
        prompt: String,
        options: DiagnosisGenerationSettings
    ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: error)
        }
    }
}

private func stoppedContainer(id: String) -> ContainerDetail {
    ContainerDetail(
        id: id,
        image: "app:1",
        status: .stopped,
        command: ["app"],
        createdAt: .now,
        startedAt: nil,
        exitCode: 1,
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
    )
}

private func runningContainer(id: String) -> ContainerDetail {
    ContainerDetail(
        id: id,
        image: "app:1",
        status: .running,
        command: ["app"],
        createdAt: .now,
        startedAt: .now,
        exitCode: nil,
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
    )
}
