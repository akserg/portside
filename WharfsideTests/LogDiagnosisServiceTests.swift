// WharfsideTests/LogDiagnosisServiceTests.swift
// CI-safe diagnosis service logic — no Apple Intelligence required.

import Foundation
import FoundationModels
import Testing
import WharfsideAnalysis
@testable import Wharfside

// MARK: - Test doubles

final class StubDiagnosisSession: DiagnosisSessioning, @unchecked Sendable {
  enum Mode: Sendable {
    case hang
    case emit(ContainerDiagnosis)
    case emitSequence([ContainerDiagnosis])
    case delayedEmit(ContainerDiagnosis, delay: Duration)
  }

  let mode: Mode
  private let lock = NSLock()
  private var _prewarmCallCount = 0
  private var _streamCallCount = 0
  private var _sequenceIndex = 0
  private var _lastOptions: DiagnosisGenerationSettings?

  var prewarmCallCount: Int { lock.withLock { _prewarmCallCount } }
  var streamCallCount: Int { lock.withLock { _streamCallCount } }
  var lastOptions: DiagnosisGenerationSettings? { lock.withLock { _lastOptions } }

  init(mode: Mode) {
    self.mode = mode
  }

  func prewarm(instructions: String) async throws {
    lock.withLock { _prewarmCallCount += 1 }
  }

  func stream(
    instructions: String,
    prompt: String,
    options: DiagnosisGenerationSettings
  ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
    lock.withLock {
      _streamCallCount += 1
      _lastOptions = options
    }
    let diagnosis: ContainerDiagnosis
    switch mode {
    case .hang:
      return hangStream()
    case .emit(let value):
      diagnosis = value
    case .emitSequence(let values):
      diagnosis = lock.withLock {
        let index = min(_sequenceIndex, values.count - 1)
        _sequenceIndex += 1
        return values[index]
      }
    case .delayedEmit(let value, let delay):
      return delayedStream(value, delay: delay)
    }
    return emitStream(diagnosis)
  }

  private func emitStream(
    _ diagnosis: ContainerDiagnosis
  ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
    AsyncThrowingStream { continuation in
      continuation.yield(diagnosis.asPartial)
      continuation.finish()
    }
  }

  private func hangStream() -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        try? await Task.sleep(for: .seconds(120))
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }

  private func delayedStream(
    _ diagnosis: ContainerDiagnosis,
    delay: Duration
  ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        try await Task.sleep(for: delay)
        continuation.yield(diagnosis.asPartial)
        continuation.finish()
      }
      continuation.onTermination = { @Sendable _ in
        task.cancel()
      }
    }
  }
}

private extension ContainerDiagnosis {
  var asPartial: PartiallyGenerated {
    asPartiallyGenerated()
  }
}

private func sampleDetail(
  id: String = "app",
  status: ContainerRuntimeStatus = .stopped,
  exitCode: Int32? = nil
) -> ContainerDetail {
  ContainerDetail(
    id: id,
    image: "app:1",
    status: status,
    command: ["app"],
    createdAt: .now,
    startedAt: nil,
    exitCode: exitCode,
    restartCount: 0,
    ports: [],
    mounts: [],
    environment: [],
    networks: []
  )
}

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
      sessionFactory: capturing
    )

    _ = try await service.diagnose(
      container: sampleDetail(exitCode: nil),
      entries: sampleEntries()
    )

    let prompt = try #require(capturing.lastPrompt)
    #expect(!prompt.contains("EXIT_CODE:"))
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

// MARK: - Helpers

private let sampleDiagnosis = ContainerDiagnosis(
  summary: "Connection refused.",
  category: .dependencyUnreachable,
  suggestedActions: ["Inspect logs"],
  confidence: .high
)

private func sampleEntries() -> [LogEntry] {
  [
    LogEntry(
      timestamp: Date(timeIntervalSince1970: 1_700_000_000),
      level: .error,
      message: "connection refused",
      raw: "ERROR: connection refused"
    )
  ]
}

final class CapturingDiagnosisSession: DiagnosisSessioning, @unchecked Sendable {
  private let lock = NSLock()
  private var _lastPrompt: String?

  var lastPrompt: String? {
    lock.withLock { _lastPrompt }
  }

  func prewarm(instructions: String) async throws {}

  func stream(
    instructions: String,
    prompt: String,
    options: DiagnosisGenerationSettings
  ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
    lock.withLock { _lastPrompt = prompt }
    return StubDiagnosisSession(mode: .emit(sampleDiagnosis)).stream(
      instructions: instructions,
      prompt: prompt,
      options: options
    )
  }
}
