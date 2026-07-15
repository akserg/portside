// WharfsideTests/LogDiagnosisServiceTests.swift
// CI-safe diagnosis service logic — no Apple Intelligence required.

import Foundation
import FoundationModels
import Testing
import WharfsideAnalysis
@testable import Wharfside

// MARK: - Tests

@MainActor
@Suite struct LogDiagnosisServiceTests {
  @Test func diagnoseThrowsWhenAIUnavailable() async {
    let session = StubDiagnosisSession(mode: .emit(sampleDiagnosis))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.heuristicsOnly(.appleIntelligenceNotEnabled)]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    do {
      _ = try await service.diagnose(container: sampleDetail(), entries: [])
      Issue.record("Expected aiUnavailable")
    } catch let error as DiagnosisError {
      if case .aiUnavailable(let reason) = error {
        #expect(reason == .appleIntelligenceNotEnabled)
      } else {
        Issue.record("Wrong DiagnosisError case: \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
    #expect(session.streamCallCount == 0)
  }

  @Test func prewarmThrowsWhenAIUnavailable() async {
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.heuristicsOnly(.deviceNotEligible)]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: StubDiagnosisSession(mode: .hang)
    )

    do {
      try await service.prewarm()
      Issue.record("Expected aiUnavailable")
    } catch let error as DiagnosisError {
      if case .aiUnavailable(let reason) = error {
        #expect(reason == .deviceNotEligible)
      } else {
        Issue.record("Wrong DiagnosisError case: \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func diagnoseTimesOutWhenSessionHangs() async {
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: StubDiagnosisSession(mode: .hang)
    )

    do {
      _ = try await service.diagnose(container: sampleDetail(), entries: sampleEntries())
      Issue.record("Expected timedOut")
    } catch let error as DiagnosisError {
      if case .timedOut = error {
        #expect(Bool(true))
      } else {
        Issue.record("Wrong DiagnosisError case: \(error)")
      }
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func diagnoseCancelsWhenTaskCancelled() async {
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: StubDiagnosisSession(mode: .hang)
    )

    let task = Task {
      try await service.diagnose(container: sampleDetail(), entries: sampleEntries())
    }
    // Give the task a chance to enter `diagnose` before cancellation.
    try? await Task.sleep(for: .milliseconds(10))
    task.cancel()

    do {
      _ = try await task.value
      Issue.record("Expected cancellation")
    } catch let error as DiagnosisError {
      if case .cancelled = error {
        #expect(Bool(true))
      } else {
        Issue.record("Wrong DiagnosisError case: \(error)")
      }
    } catch is CancellationError {
      // If cancellation lands before our service maps the error, this is still valid.
      #expect(Bool(true))
    } catch {
      Issue.record("Unexpected error: \(error)")
    }
  }

  @Test func diagnoseReturnsTypedResultFromStream() async throws {
    let expected = ContainerDiagnosis(
      summary: "Dependency unreachable.",
      category: .dependencyUnreachable,
      suggestedActions: ["Check database host", "Verify network"],
      confidence: .high
    )
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: StubDiagnosisSession(mode: .emit(expected))
    )

    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )
    #expect(result.diagnosis == expected)
    #expect(!result.wasDegraded)
    #expect(result.telemetry.retryCount == 0)
  }

  @Test func prewarmSucceedsWhenAvailable() async throws {
    let session = StubDiagnosisSession(mode: .emit(sampleDiagnosis))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    try await service.prewarm()
    #expect(session.prewarmCallCount == 1)
  }

  @Test func digestOmitsExitCodeWhenUnknown() async throws {
    let capturing = CapturingDiagnosisSession()
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      containerService: ExitStatusStubContainerService(
        exitStatus: .unavailable(reason: .runtimeGone)
      ),
      sessionFactory: capturing
    )

    _ = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )

    let prompt = try #require(capturing.lastPrompt)
    #expect(!prompt.contains("EXIT_CODE:"))
  }

  @Test func diagnosisRefreshesExitStatusFromRuntime() async throws {
    let capturing = CapturingDiagnosisSession()
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      containerService: ExitStatusStubContainerService(exitStatus: .known(137, source: .runtime)),
      sessionFactory: capturing
    )

    _ = try await service.diagnose(
      container: sampleDetail(exitStatus: .unavailable(reason: .noEvidence)),
      entries: sampleEntries()
    )

    let prompt = try #require(capturing.lastPrompt)
    #expect(prompt.contains("EXIT_CODE: 137"))
    #expect(!prompt.contains("(from boot log)"))
  }

  @Test func diagnosisFallsBackToBootLogExitWhenRuntimeGone() async throws {
    let session = StubDiagnosisSession(mode: .emit(sampleDiagnosis))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      containerService: ExitStatusStubContainerService(exitStatus: .unavailable(reason: .runtimeGone)),
      sessionFactory: session
    )

    // Full stop signature short-circuits via precheck; exit evidence still comes from boot log.
    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: userStopBootLogEntries()
    )

    #expect(result.renderedDigest.contains("EXIT_CODE: 137 (from boot log)"))
    #expect(session.streamCallCount == 0)
    #expect(result.source == .deterministicPrecheck(ruleID: "precheck.stop-escalation"))
  }

  @Test func digestUsesLifecycleRestartCount() async throws {
    let capturing = CapturingDiagnosisSession()
    let observer = ContainerLifecycleObserver()
    await observer.record(containers: [
      ContainerSummary(id: "app", image: "app:1", status: .running, startedAt: nil, portSummary: "—")
    ])
    await observer.record(containers: [
      ContainerSummary(id: "app", image: "app:1", status: .stopped, startedAt: nil, portSummary: "—")
    ])
    await observer.record(containers: [
      ContainerSummary(id: "app", image: "app:1", status: .running, startedAt: nil, portSummary: "—")
    ])

    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: observer,
      sessionFactory: capturing
    )

    _ = try await service.diagnose(
      container: sampleDetail(id: "app"),
      entries: sampleEntries()
    )

    let prompt = try #require(capturing.lastPrompt)
    #expect(prompt.contains("RESTARTS: 1"))
  }

  @Test func diagnoseRetriesOnceWhenValidatorFails() async throws {
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

    #expect(session.streamCallCount == 2)
    #expect(result.diagnosis == fixed)
    #expect(result.telemetry.retryCount == 1)
    #expect(!result.wasDegraded)
  }

  @Test func diagnoseDegradesWhenRetryStillViolates() async throws {
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

    #expect(session.streamCallCount == 2)
    #expect(result.wasDegraded)
    #expect(result.diagnosis.confidence == .low)
    #expect(result.diagnosis.category == .dependencyUnreachable)
    #expect(result.telemetry.retryCount == 1)
  }

  @Test func diagnoseRepairsDockerVocabularyWithoutRetry() async throws {
    let withDocker = ContainerDiagnosis(
      summary: "Database connection refused.",
      category: .dependencyUnreachable,
      suggestedActions: ["Run docker logs api", "Check host"],
      confidence: .high
    )
    let session = StubDiagnosisSession(mode: .emit(withDocker))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    let result = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries()
    )

    #expect(session.streamCallCount == 1)
    #expect(result.diagnosis.suggestedActions.first?.contains("container logs") == true)
    #expect(!result.wasDegraded)
  }

  @Test func diagnosePassesGenerationSettingsToSession() async throws {
    let session = StubDiagnosisSession(mode: .emit(sampleDiagnosis))
    let settings = DiagnosisGenerationSettings(temperature: 0.15)
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      sessionFactory: session
    )

    _ = try await service.diagnose(
      container: sampleDetail(),
      entries: sampleEntries(),
      generationSettings: settings
    )

    #expect(session.lastOptions == settings)
  }
}
