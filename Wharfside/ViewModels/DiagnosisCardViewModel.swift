// ViewModels/DiagnosisCardViewModel.swift
// Issue 1.7 — diagnosis card state machine (renders LogDiagnosisService output only).

import Foundation
import Observation
import WharfsideAnalysis

/// Loading presentation chosen from M1.7 Step 0 latency on postgres_crash fixture:
/// prewarmed TTFT 1.63 s → skeleton shimmer until first token, then stream.
enum DiagnosisCardLoadingStyle: Equatable, Sendable {
    case directStream
    case skeletonUntilFirstToken
    case skeletonWithStatus
}

@MainActor
@Observable
final class DiagnosisCardViewModel {
    enum Phase: Equatable {
        case idle
        case running(RunningState)
        case result(ResultState)
        case failed(String)
    }

    struct RunningState: Equatable {
        var partialSummary: String?
        var hasReceivedFirstToken: Bool
    }

    struct ResultState: Equatable {
        var result: DiagnosisResult
        var isVerifying: Bool
    }

    static let loadingStyle: DiagnosisCardLoadingStyle = .skeletonUntilFirstToken
    static let logEntriesWindow: Duration = .seconds(300)

    private(set) var phase: Phase = .idle
    private(set) var observerRestartCount = 0

    private let diagnosisService: LogDiagnosisService
    private let containerService: any ContainerServicing
    private var container: ContainerDetail?
    private var resultContainerID: String?
    var logEntriesProvider: () -> [LogEntry]
    /// Wall-clock cap per cold-fetch phase (stdio / boot). Tests shorten this so a
    /// buffered diagnose is not blocked on the production 2 s XPC drain timeout.
    var coldFetchPhaseDuration: Duration = LogEntriesCollector.phaseDuration
    /// Issue 1.11 — resolved lazily at copy time so the report always carries whatever
    /// version info is cached then, without this view model owning any AppState reference.
    private let reportEnvironmentProvider: () -> DiagnosisReportEnvironment
    private var diagnosisTask: Task<Void, Never>?
    private var prewarmTask: Task<Void, Never>?
    private var copyReportBannerClearTask: Task<Void, Never>?

    /// Invoked when a diagnosis finalizes with a resolved exit status (B6 Overview backfill).
    /// Kept as a callback so this view model does not own AppState / the backfill cache.
    var onExitStatusResolved: ((String, ExitStatus) -> Void)?

    /// Transient "Report copied" confirmation, mirroring `ContainerActionCoordinator`'s
    /// banner pattern (auto-clears; the security-review reminder is the point of showing it).
    private(set) var copyReportBannerMessage: String?

    init(
        containerID: String,
        diagnosisService: LogDiagnosisService,
        containerService: any ContainerServicing,
        logEntriesProvider: @escaping () -> [LogEntry],
        reportEnvironmentProvider: @escaping () -> DiagnosisReportEnvironment = { .current(runtimeVersion: nil) }
    ) {
        self.diagnosisService = diagnosisService
        self.containerService = containerService
        self.logEntriesProvider = logEntriesProvider
        self.reportEnvironmentProvider = reportEnvironmentProvider
    }

    var isEligible: Bool {
        guard let container else { return false }
        return container.status == .stopped || observerRestartCount > 0
    }

    var isRunning: Bool {
        if case .running = phase { return true }
        return false
    }

    func updateContainer(_ detail: ContainerDetail) {
        if container?.id != detail.id {
            cancelInFlightWork(resetToIdle: true)
            resultContainerID = nil
        }
        container = detail
    }

    func updateObserverRestartCount(_ count: Int) {
        observerRestartCount = count
    }

    func onEligibleAppear() {
        guard isEligible else { return }
        prewarmTask?.cancel()
        prewarmTask = Task { [weak self] in
            guard let self else { return }
            try? await self.diagnosisService.prewarm()
        }
    }

    func onDisappear() {
        cancelInFlightWork(resetToIdle: true)
        prewarmTask?.cancel()
        prewarmTask = nil
        copyReportBannerClearTask?.cancel()
        copyReportBannerClearTask = nil
    }

    func explain() {
        guard container != nil, !isRunning else { return }
        startDiagnosis()
    }

    func regenerate() {
        guard container != nil, !isRunning else { return }
        startDiagnosis()
    }

    func retryAfterFailure() {
        guard !isRunning else { return }
        explain()
    }

    /// Formats the copyable report for the currently displayed result (any result state,
    /// including degraded). Returns nil when there's no result to report on. Pure — the
    /// caller (a View) owns the actual pasteboard write (Issue 1.11).
    func reportText() -> String? {
        guard case .result(let state) = phase, let container else { return nil }
        return DiagnosisReportFormatter.render(
            result: state.result,
            container: container,
            environment: reportEnvironmentProvider()
        )
    }

    func presentCopyConfirmation() {
        copyReportBannerClearTask?.cancel()
        copyReportBannerMessage = DiagnosisPrivacyCopy.copyReportToast
        copyReportBannerClearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.copyReportBannerMessage = nil
        }
    }

    // MARK: - Private

    private func startDiagnosis() {
        guard let container else { return }

        diagnosisTask?.cancel()
        phase = .running(
            RunningState(
                partialSummary: nil,
                hasReceivedFirstToken: false
            )
        )

        let containerID = container.id
        let detail = container
        diagnosisTask = Task { [weak self] in
            guard let self else { return }
            await self.runDiagnosis(container: detail, containerID: containerID)
        }
    }

    private func runDiagnosis(container: ContainerDetail, containerID: String) async {
        DiagnosisLog.info("diagnosis started for \(containerID)")
        do {
            let buffered = logEntriesProvider()
            let entries = await LogEntriesCollector.assembleEvidence(
                from: containerService,
                containerID: containerID,
                buffered: buffered,
                maxDuration: coldFetchPhaseDuration
            )
            DiagnosisLog.info(
                "assembled \(entries.count) evidence entries for \(containerID) "
                    + "(buffered=\(buffered.count))"
            )

            let stream = diagnosisService.streamingDiagnose(container: container, entries: entries)
            for try await event in stream {
                try Task.checkCancellation()
                switch event {
                case .exitStatusResolved(let status):
                    onExitStatusResolved?(containerID, status)
                case .partial(let partial):
                    applyPartial(partial)
                case .finalized(let result):
                    DiagnosisLog.info(
                        "diagnosis finalized for \(containerID): degraded=\(result.wasDegraded)"
                    )
                    await applyFinalized(result, containerID: containerID)
                }
            }
            if case .running = phase {
                DiagnosisLog.error("diagnosis stream ended without result for \(containerID)")
                phase = .failed("Diagnosis ended unexpectedly. Try again.")
            }
        } catch let error as DiagnosisError {
            DiagnosisLog.error("diagnosis error for \(containerID): \(String(describing: error))")
            handleDiagnosisError(error)
        } catch is CancellationError {
            DiagnosisLog.info("diagnosis cancelled for \(containerID)")
            if resultContainerID != containerID {
                phase = .idle
            }
        } catch {
            DiagnosisLog.error("diagnosis failed for \(containerID): \(error.localizedDescription)")
            phase = .failed(error.localizedDescription)
        }
    }

    private func applyPartial(_ partial: ContainerDiagnosis.PartiallyGenerated) {
        guard case .running(var state) = phase else { return }
        let text = Self.displayText(from: partial)
        if !text.isEmpty {
            state.partialSummary = text
            state.hasReceivedFirstToken = true
        }
        phase = .running(state)
    }

    private func applyFinalized(_ result: DiagnosisResult, containerID: String) async {
        // Exit status is published earlier via `.exitStatusResolved` (pre-model), so Overview
        // backfill does not wait on — or depend on — the model finalizing here.
        phase = .result(ResultState(result: result, isVerifying: true))
        resultContainerID = containerID

        try? await Task.sleep(for: .milliseconds(200))
        guard !Task.isCancelled else { return }

        if case .result(var state) = phase, state.result == result {
            state.isVerifying = false
            phase = .result(state)
        }
    }

    private func handleDiagnosisError(_ error: DiagnosisError) {
        switch error {
        case .aiUnavailable:
            phase = .idle
        case .timedOut:
            phase = .failed("Diagnosis timed out. Try again.")
        case .cancelled:
            phase = .idle
        case .incompleteResponse:
            phase = .failed("The model returned an incomplete response. Try again.")
        }
    }

    private func cancelInFlightWork(resetToIdle: Bool) {
        diagnosisTask?.cancel()
        diagnosisTask = nil
        if resetToIdle, resultContainerID == nil {
            phase = .idle
        } else if resetToIdle, case .running = phase {
            phase = .idle
        }
    }

    static func displayText(from partial: ContainerDiagnosis.PartiallyGenerated) -> String {
        partial.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

#if DEBUG
extension DiagnosisCardViewModel {
    static func preview(
        phase: Phase,
        containerID: String = "db"
    ) -> DiagnosisCardViewModel {
        let vm = DiagnosisCardViewModel(
            containerID: containerID,
            diagnosisService: LogDiagnosisService(
                availability: DiagnosisCardPreviewAvailability(),
                lifecycleObserver: ContainerLifecycleObserver()
            ),
            containerService: PreviewLogContainerService(),
            logEntriesProvider: { [] }
        )
        vm.updateContainer(
            ContainerDetail(
                id: containerID,
                image: "postgres:16",
                status: .stopped,
                command: ["postgres"],
                createdAt: .now,
                startedAt: nil,
                exitStatus: .known(1, source: .runtime),
                restartCount: 0,
                ports: [],
                mounts: [],
                environment: [],
                networks: []
            )
        )
        vm.phase = phase
        return vm
    }

    /// Injects a completed diagnosis without the 200 ms verifying shimmer — launch assets.
    func applyCompletedResult(_ result: DiagnosisResult) {
        cancelInFlightWork(resetToIdle: false)
        phase = .result(ResultState(result: result, isVerifying: false))
        resultContainerID = container?.id
        if let id = container?.id {
            onExitStatusResolved?(id, result.exitStatus)
        }
    }

    func applyRunningPartial(_ summary: String?) {
        cancelInFlightWork(resetToIdle: false)
        phase = .running(
            RunningState(
                partialSummary: summary,
                hasReceivedFirstToken: summary != nil
            )
        )
    }

    func applyIdlePhase() {
        cancelInFlightWork(resetToIdle: true)
        phase = .idle
    }

    func presentCopyConfirmationForSnapshot() {
        copyReportBannerMessage = DiagnosisPrivacyCopy.copyReportToast
    }
}

private struct DiagnosisCardPreviewAvailability: AvailabilityProviding {
    func currentCapability() -> AICapability { .full }
}

private struct PreviewLogContainerService: ContainerServicing {
    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail { fatalError() }
    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}
    func stats(id: String) async throws -> ContainerStats { fatalError() }
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
    func exitStatus(id: String) async -> ExitStatus { .unavailable(reason: .noEvidence) }
}
#endif
