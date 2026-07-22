// Debug/LaunchAssets/FixtureReplay.swift
// B5 — reuses the B4 report2 diagnose path (precheck short-circuit, no live model).

#if DEBUG
import Foundation
import FoundationModels
import WharfsideAnalysis

/// Loads analysis fixtures and runs the same deterministic diagnose path as
/// `LogDiagnosisServiceReport2Tests` — model session is stubbed and must not be invoked
/// for the report2 / Digest16 hero case.
enum FixtureReplay {
    static let report2LogName = "stop_timeout_misdiagnosed_as_oom.log"
    static let noisyLogName = "boot_noise_contamination.log"

    static func fixturesDirectory() -> URL? {
        if let root = ProcessInfo.processInfo.environment["WHARFSIDE_REPO_ROOT"], !root.isEmpty {
            let url = URL(fileURLWithPath: root, isDirectory: true)
                .appendingPathComponent("Packages/WharfsideAnalysis/Tests/Fixtures", isDirectory: true)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }

        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<8 {
            url.deleteLastPathComponent()
            let candidate = url
                .appendingPathComponent("Packages/WharfsideAnalysis/Tests/Fixtures", isDirectory: true)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func loadBootLog(named filename: String) throws -> [LogEntry] {
        guard let directory = fixturesDirectory() else {
            throw FixtureReplayError.fixturesDirectoryNotFound
        }
        let url = directory.appendingPathComponent(filename)
        let text = try String(contentsOf: url, encoding: .utf8)
        return LogParser().parse(text: text).map { entry in
            LogEntry(
                timestamp: entry.timestamp,
                level: entry.level,
                message: entry.message,
                raw: entry.raw,
                source: .boot
            )
        }
    }

    static func loadLogChunks(named filename: String, source: LogSource = .boot) throws -> [LogChunk] {
        guard let directory = fixturesDirectory() else {
            throw FixtureReplayError.fixturesDirectoryNotFound
        }
        let url = directory.appendingPathComponent(filename)
        let text = try String(contentsOf: url, encoding: .utf8)
        let data = Data(text.utf8)
        return [LogChunk(source: source, data: data)]
    }

    @MainActor
    static func diagnoseReport2() async throws -> (container: ContainerDetail, result: DiagnosisResult) {
        let entries = try loadBootLog(named: report2LogName)
        let container = helloContainerDetail()
        let session = LaunchAssetStubDiagnosisSession(mode: .emit(oomMisdiagnosis))
        let service = LogDiagnosisService(
            availability: LaunchAssetFixedAvailability(capability: .full),
            lifecycleObserver: ContainerLifecycleObserver(),
            containerService: LaunchAssetExitStatusStub(exitStatus: .unavailable(reason: .runtimeGone)),
            sessionFactory: session
        )
        let result = try await service.diagnose(container: container, entries: entries)
        guard session.streamCallCount == 0 else {
            throw FixtureReplayError.modelInvokedUnexpectedly
        }
        guard result.source == .deterministicPrecheck(ruleID: "precheck.stop-escalation") else {
            throw FixtureReplayError.unexpectedDiagnosisSource
        }
        return (container, result)
    }

    static func helloContainerDetail() -> ContainerDetail {
        ContainerDetail(
            id: "hello",
            image: "docker.io/library/alpine:latest",
            status: .stopped,
            command: ["/bin/sh"],
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            startedAt: nil,
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0,
            ports: [],
            mounts: [],
            environment: [],
            networks: []
        )
    }

    static func reportEnvironment() -> DiagnosisReportEnvironment {
        // Deterministic display clock for launch stills (not live wall time).
        // Tag-day: bump `generatedAt` near the 0.1.1 cut so report-markdown isn't a
        // month-old stamp on a just-launched product — then `make snapshot-assets` once
        // (only report-markdown + GIF need refreshing). See docs/LAUNCH_ASSETS.md.
        DiagnosisReportEnvironment(
            wharfsideVersion: "0.1.1",
            runtimeVersionLabel: "1.0.0 (commit ee848e3)",
            macOSVersion: "26.5.2",
            generatedAt: Date(timeIntervalSince1970: 1_784_699_697) // 2026-07-22T05:54:57Z
        )
    }

    /// Historical wrong OOM diagnosis (ManualTesting/report2.md shape) for contrast stills.
    static let oomMisdiagnosis = ContainerDiagnosis(
        summary: "The container exited due to a memory threshold exceeded by vminitd.",
        category: .outOfMemory,
        suggestedActions: ["Increase memory limit"],
        confidence: .medium
    )

    static func wrongDiagnosisResult(renderedDigest: String) -> DiagnosisResult {
        DiagnosisResult(
            diagnosis: oomMisdiagnosis,
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
            renderedDigest: renderedDigest,
            ruleMetadata: .empty,
            source: .onDeviceModel
        )
    }
}

enum FixtureReplayError: Error, LocalizedError {
    case fixturesDirectoryNotFound
    case modelInvokedUnexpectedly
    case unexpectedDiagnosisSource

    var errorDescription: String? {
        switch self {
        case .fixturesDirectoryNotFound:
            "Could not locate Packages/WharfsideAnalysis/Tests/Fixtures — set WHARFSIDE_REPO_ROOT"
        case .modelInvokedUnexpectedly:
            "Fixture replay invoked the model session; expected precheck short-circuit"
        case .unexpectedDiagnosisSource:
            "Fixture replay did not yield deterministic precheck.stop-escalation"
        }
    }
}

// MARK: - Minimal stubs (app DEBUG; mirrors WharfsideTests doubles)

struct LaunchAssetFixedAvailability: AvailabilityProviding {
    let capability: AICapability
    func currentCapability() -> AICapability { capability }
}

final class LaunchAssetStubDiagnosisSession: DiagnosisSessioning, @unchecked Sendable {
    enum Mode: Sendable {
        case emit(ContainerDiagnosis)
    }

    let mode: Mode
    private let lock = NSLock()
    private var _streamCallCount = 0
    var streamCallCount: Int { lock.withLock { _streamCallCount } }

    init(mode: Mode) {
        self.mode = mode
    }

    func prewarm(instructions: String) async throws {}

    func stream(
        instructions: String,
        prompt: String,
        options: DiagnosisGenerationSettings
    ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
        lock.withLock { _streamCallCount += 1 }
        let diagnosis: ContainerDiagnosis
        switch mode {
        case .emit(let value):
            diagnosis = value
        }
        return AsyncThrowingStream { continuation in
            continuation.yield(diagnosis.asPartiallyGenerated())
            continuation.finish()
        }
    }
}

final class LaunchAssetExitStatusStub: ContainerServicing, @unchecked Sendable {
    let exitStatus: ExitStatus

    init(exitStatus: ExitStatus) {
        self.exitStatus = exitStatus
    }

    func list() async throws -> [ContainerSummary] { [] }
    func get(id: String) async throws -> ContainerDetail { fatalError("unused in fixture replay") }
    func exitStatus(id: String) async -> ExitStatus { exitStatus }
    func create(id: String, image: String, command: [String]) async throws {}
    func start(id: String) async throws {}
    func stop(id: String, timeout: TimeInterval) async throws {}
    func kill(id: String, signal: String) async throws {}
    func delete(id: String, force: Bool) async throws {}
    func stats(id: String) async throws -> ContainerStats { fatalError("unused") }
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { $0.finish() }
    }
    func exec(id: String, command: [String]) async throws -> ExecResult {
        ExecResult(exitCode: 0, stdout: "", stderr: "")
    }
}
#endif
