// WharfsideTests/DiagnosisLatencyTests.swift
// Issue 1.7 Step 0 — TTFT / completion latency for loading-design branch.
// Run: touch .artifacts/.run-ai-regression && xcodebuild test ... -only-testing:WharfsideTests/DiagnosisLatencyTests

#if canImport(FoundationModels)
import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

private enum LatencyGate {
    static var isEnabled: Bool {
        let marker = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".artifacts/.run-ai-regression")
        return FileManager.default.fileExists(atPath: marker.path)
    }
}

@Suite
@MainActor
struct DiagnosisLatencyTests {
    private static let postgresFixture: DiagnosisRegressionFixture = {
        DiagnosisRegressionFixture.all.first { $0.name == "postgres_crash" }!
    }()

    @Test func measureDiagnosisLatency() async throws {
        guard LatencyGate.isEnabled else { return }

        let fixture = Self.postgresFixture
        let service = LogDiagnosisService(
            availability: SystemModelAvailabilityProvider(),
            lifecycleObserver: ContainerLifecycleObserver()
        )

        // Cold — no prewarm
        let cold = try await measureRun(service: service, fixture: fixture, prewarmFirst: false)

        // Prewarmed — prewarm ≥5 s earlier
        try await service.prewarm()
        try await Task.sleep(for: .seconds(5))
        let prewarmed = try await measureRun(service: service, fixture: fixture, prewarmFirst: false)

        let table = """
        | Scenario | Time to first token | Time to complete |
        |----------|--------------------:|-----------------:|
        | Cold (no prewarm) | \(format(cold.ttft)) | \(format(cold.complete)) |
        | Prewarmed (prewarm() ≥5 s earlier) | \(format(prewarmed.ttft)) | \(format(prewarmed.complete)) |
        """
        print("\n=== M1.7 Latency Table ===\n\(table)\n")

        let artifact = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".artifacts/diagnosis-latency.md")
        try FileManager.default.createDirectory(
            at: artifact.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try table.write(to: artifact, atomically: true, encoding: .utf8)
    }

    private struct Timings {
        var ttft: Duration?
        var complete: Duration
    }

    private func measureRun(
        service: LogDiagnosisService,
        fixture: DiagnosisRegressionFixture,
        prewarmFirst: Bool
    ) async throws -> Timings {
        if prewarmFirst {
            try await service.prewarm()
        }

        let start = ContinuousClock.now
        var ttft: Duration?
        let stream = service.streamDiagnosis(container: fixture.container, entries: fixture.entries)
        for try await _ in stream where ttft == nil {
            ttft = start.duration(to: .now)
        }
        let complete = start.duration(to: .now)
        return Timings(ttft: ttft, complete: complete)
    }

    private func format(_ duration: Duration?) -> String {
        guard let duration else { return "—" }
        let ms = duration.milliseconds
        if ms >= 1000 {
            return String(format: "%.2f s", ms / 1000)
        }
        return String(format: "%.0f ms", ms)
    }
}

private extension Duration {
    var milliseconds: Double {
        let components = components
        let secondsMs = Double(components.seconds) * 1000
        let attosMs = Double(components.attoseconds) / 1_000_000_000_000_000
        return secondsMs + attosMs
    }
}
#endif
