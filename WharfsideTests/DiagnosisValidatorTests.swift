// WharfsideTests/DiagnosisValidatorTests.swift
// Issue 1.6.1 — CI-safe validator rule coverage.

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@Suite @MainActor struct DiagnosisValidatorTests {
  private let validator = DiagnosisValidator()

  @Test func unknownDespiteErrorsWhenErrorsPresent() {
    let digest = makeDigest(counts: ["ERROR": 2, "INFO": 1])
    let diagnosis = makeDiagnosis(category: .unknown)
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(violations.contains(.unknownDespiteErrors(errorCount: 2)))
  }

  @Test func passesWhenUnknownWithCleanLogs() {
    let digest = makeDigest(counts: ["INFO": 3], exitStatus: .known(0, source: .runtime))
    let diagnosis = makeDiagnosis(category: .unknown, confidence: .low)
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
  #expect(violations.isEmpty)
  }

  @Test func categoryWithoutEvidenceWhenNoErrors() {
    let digest = makeDigest(counts: ["INFO": 2], exitStatus: .known(0, source: .runtime))
    let diagnosis = makeDiagnosis(category: .configuration)
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(violations.contains(.categoryWithoutEvidence(category: .configuration)))
  }

  @Test func allowsCategoryWhenOOMSignalInPatterns() {
    let digest = makeDigest(
      counts: ["INFO": 1],
      patterns: [
        LogPattern(
          template: "Killed",
          count: 1,
          firstSeen: .now,
          lastSeen: .now,
          sampleRaw: "Killed"
        )
      ]
    )
    let diagnosis = makeDiagnosis(category: .outOfMemory)
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(!violations.contains(.categoryWithoutEvidence(category: .outOfMemory)))
  }

  @Test func fabricatedEvidenceDetectsMissingTerm() {
    let digest = makeDigest(counts: ["ERROR": 1], lastError: "something failed")
    let diagnosis = makeDiagnosis(
      category: .applicationBug,
      summary: "Likely stack overflow in the worker."
    )
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(violations.contains(.fabricatedEvidence(term: "stack overflow")))
  }

  @Test func fabricatedEvidencePassesWhenTermInDigest() {
    let digest = makeDigest(
      counts: ["ERROR": 1],
      lastError: "FATAL: connection refused to database"
    )
    let diagnosis = makeDiagnosis(
      category: .dependencyUnreachable,
      summary: "Database connection refused."
    )
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(!violations.contains(.fabricatedEvidence(term: "connection refused")))
  }

  @Test func wrongCLIVocabularyDetected() {
    let digest = makeDigest(counts: ["ERROR": 1])
    let diagnosis = makeDiagnosis(
      category: .configuration,
      actions: ["Run docker logs db", "Free disk space"]
    )
    let violations = validator.validate(diagnosis, against: digest, renderedDigest: render(digest))
    #expect(violations.contains(.wrongCLIVocabulary(action: "Run docker logs db")))
  }

  @Test func repairRewritesDockerLogs() {
    var validator = DiagnosisValidator()
    var diagnosis = makeDiagnosis(
      category: .dependencyUnreachable,
      actions: ["Run docker logs api"]
    )
    let changed = validator.repairVocabulary(&diagnosis)
    #expect(changed)
    #expect(diagnosis.suggestedActions == ["Run container logs api"])
  }

  @Test func repairDropsDockerCompose() {
    var validator = DiagnosisValidator()
    var diagnosis = makeDiagnosis(
      category: .configuration,
      actions: ["docker-compose up -d", "container inspect app"]
    )
    let changed = validator.repairVocabulary(&diagnosis)
    #expect(changed)
    #expect(diagnosis.suggestedActions == ["container inspect app"])
  }

  @Test func repairDropsUnmappableDockerCommand() {
    var validator = DiagnosisValidator()
    var diagnosis = makeDiagnosis(
      category: .configuration,
      actions: ["Use docker run to recreate"]
    )
    let changed = validator.repairVocabulary(&diagnosis)
    #expect(changed)
    #expect(diagnosis.suggestedActions.isEmpty)
  }

  @Test func degradeBuildsFactSummary() {
    let digest = makeDigest(
      counts: ["ERROR": 2],
      exitStatus: .known(1, source: .runtime),
      lastError: "ERROR: No space left on device"
    )
    let degraded = validator.degrade(
      diagnosis: makeDiagnosis(category: .unknown),
      digest: digest,
      violations: [.unknownDespiteErrors(errorCount: 2)]
    )
    #expect(degraded.confidence == .low)
    #expect(degraded.summary.contains("2 ERROR/WARN"))
    #expect(degraded.summary.contains("No space left on device"))
    #expect(degraded.category == .configuration)
  }

  @Test func degradeUsesUnknownForCleanExitViolation() {
    let digest = makeDigest(counts: ["INFO": 2], exitStatus: .known(0, source: .runtime))
    let degraded = validator.degrade(
      diagnosis: makeDiagnosis(category: .configuration),
      digest: digest,
      violations: [.categoryWithoutEvidence(category: .configuration)]
    )
    #expect(degraded.category == .unknown)
    #expect(degraded.confidence == .low)
  }

  @Test func validationIsDeterministic() {
    let digest = makeDigest(counts: ["ERROR": 1], lastError: "ERROR: boom")
    let diagnosis = makeDiagnosis(category: .unknown, summary: "Stack overflow suspected.")
    let rendered = render(digest)
    let first = validator.validate(diagnosis, against: digest, renderedDigest: rendered)
    let second = validator.validate(diagnosis, against: digest, renderedDigest: rendered)
    #expect(first == second)
  }

  @Test func correctionLinesNameViolatedRules() {
    let digest = makeDigest(counts: ["ERROR": 2])
    let lines = validator.correctionLines(
      for: [.unknownDespiteErrors(errorCount: 2), .fabricatedEvidence(term: "disk full")],
      digest: digest
    )
    #expect(lines.count == 2)
    #expect(lines[0].contains("2"))
    #expect(lines[1].contains("disk full"))
  }
}

// MARK: - Helpers

private func makeDigest(
  counts: [String: Int],
  exitStatus: WharfsideAnalysis.ExitStatus = .known(1, source: .runtime),
  lastError: String? = nil,
  firstError: String? = nil,
  patterns: [LogPattern] = []
) -> LogDigest {
  LogDigest(
    containerName: "app",
    image: "app:1",
    exitStatus: exitStatus,
    windowDescription: "test",
    counts: counts,
    topPatterns: patterns,
    firstError: firstError,
    lastError: lastError,
    lastLines: lastError.map { [$0] } ?? [],
    restartCount: 0
  )
}

private func makeDiagnosis(
  category: FailureCategory,
  summary: String = "Summary.",
  actions: [String] = ["Inspect logs"],
  confidence: Confidence = .medium
) -> ContainerDiagnosis {
  ContainerDiagnosis(
    summary: summary,
    category: category,
    suggestedActions: actions,
    confidence: confidence
  )
}

private func render(_ digest: LogDigest) -> String {
  PromptRenderer().render(digest)
}
