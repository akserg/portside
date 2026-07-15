// WharfsideTests/LogDiagnosisServiceTestDoubles.swift
// Shared stubs for LogDiagnosisServiceTests.

import Foundation
import FoundationModels
import WharfsideAnalysis
@testable import Wharfside

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

extension ContainerDiagnosis {
  var asPartial: PartiallyGenerated {
    asPartiallyGenerated()
  }
}

let sampleDiagnosis = ContainerDiagnosis(
  summary: "Connection refused.",
  category: .dependencyUnreachable,
  suggestedActions: ["Inspect logs"],
  confidence: .high
)

func sampleDetail(
  id: String = "app",
  image: String = "app:1",
  status: ContainerRuntimeStatus = .stopped,
  exitStatus: WharfsideAnalysis.ExitStatus = .unavailable(reason: .noEvidence)
) -> ContainerDetail {
  ContainerDetail(
    id: id,
    image: image,
    status: status,
    command: ["app"],
    createdAt: .now,
    startedAt: nil,
    exitStatus: exitStatus,
    restartCount: 0,
    ports: [],
    mounts: [],
    environment: [],
    networks: []
  )
}

final class ExitStatusStubContainerService: ContainerServicing, @unchecked Sendable {
  let exitStatus: WharfsideAnalysis.ExitStatus

  init(exitStatus: WharfsideAnalysis.ExitStatus) {
    self.exitStatus = exitStatus
  }

  func list() async throws -> [ContainerSummary] { [] }
  func get(id: String) async throws -> ContainerDetail { fatalError() }
  func exitStatus(id: String) async -> WharfsideAnalysis.ExitStatus { exitStatus }
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
}

func userStopBootLogEntries() -> [LogEntry] {
  [
    LogEntry(
      timestamp: nil,
      level: .info,
      message: "id: hello sending signal 15 to process 109",
      raw: "2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109",
      source: .boot
    ),
    LogEntry(
      timestamp: nil,
      level: .info,
      message: "id: hello sending signal 9 to process 109",
      raw: "2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109",
      source: .boot
    ),
    LogEntry(
      timestamp: nil,
      level: .info,
      message: "id: hello, status: 137 managed process exit",
      raw: "2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit",
      source: .boot
    )
  ]
}

func sampleEntries() -> [LogEntry] {
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
