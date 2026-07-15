// WharfsideTests/DiagnosisResultRetentionTests.swift
// Issue 1.11 — `DiagnosisResult.renderedDigest` must carry what the FINAL generation
// attempt actually saw, including through the retry/degrade path.

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
@Suite struct DiagnosisResultRetentionTests {
  @Test func retainsFinalPromptOnFirstAttempt() async throws {
    let capturing = CapturingDiagnosisSession()
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: capturing
    )

    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )

    let prompt = try #require(capturing.lastPrompt)
    #expect(result.renderedDigest == prompt)
    #expect(!result.renderedDigest.contains("CORRECTION:"))
  }

  @Test func retainsFinalPromptThroughRetryPath() async throws {
    let violating = ContainerDiagnosis(
      summary: "Unknown failure.",
      category: .unknown,
      suggestedActions: ["Inspect logs"],
      confidence: .low
    )
    let fixed = ContainerDiagnosis(
      summary: "Connection refused to database.",
      category: .dependencyUnreachable,
      suggestedActions: ["Check database host"],
      confidence: .high
    )
    let session = StubDiagnosisSession(mode: .emitSequence([violating, fixed]))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )

    #expect(result.telemetry.retryCount == 1)
    // The stored digest must carry what the FINAL (retried) generation saw, not the
    // original pre-correction render.
    #expect(result.renderedDigest.contains("CORRECTION:"))
  }

  @Test func retainsFinalPromptWhenDegraded() async throws {
    let violating = ContainerDiagnosis(
      summary: "Unknown failure.",
      category: .unknown,
      suggestedActions: ["Inspect logs"],
      confidence: .high
    )
    let session = StubDiagnosisSession(mode: .emitSequence([violating, violating]))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )

    #expect(result.wasDegraded)
    #expect(result.renderedDigest.contains("CORRECTION:"))
  }
}

private func sampleDetail() -> ContainerDetail {
  ContainerDetail(
    id: "app",
    image: "app:1",
    status: .stopped,
    command: ["app"],
    createdAt: .now,
    startedAt: nil,
    exitStatus: .unavailable(reason: .noEvidence),
    restartCount: 0,
    ports: [],
    mounts: [],
    environment: [],
    networks: []
  )
}
