// WharfsideTests/DiagnosisRegressionTests.swift
// Issue 1.6 / 1.8 — prompt regression against real FoundationModels output.
// Enabled when `.artifacts/.run-ai-regression` exists (see Makefile `ai-test`).
//
// Two-tier suite (B4):
// - Deterministic / `make ci`: LogDiagnosisServiceReport2Tests (hello / Digest16) —
//   model never invoked; do not wire report2 into this live-model suite.
// - Nightly / `make ai-test`: this file — genuine synthesis cases (e.g. crashy /
//   boot_noise_contamination). Digest15 formatter golden covers the model-path
//   report *shape* without requiring FoundationModels in CI.

#if canImport(FoundationModels)
import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

private enum AIRegressionGate {
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
struct DiagnosisRegressionTests {
  private static let runsPerFixture = 3
  private static let artifactsDirectory: URL = {
    let root = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    return root.appendingPathComponent(".artifacts/diagnosis-regression", isDirectory: true)
  }()

  @Test(arguments: DiagnosisRegressionFixture.all)
  func fixtureMeetsTypedExpectations(_ fixture: DiagnosisRegressionFixture) async throws {
    guard AIRegressionGate.isEnabled else { return }

    try FileManager.default.createDirectory(at: Self.artifactsDirectory, withIntermediateDirectories: true)

    let service = LogDiagnosisService(
      availability: SystemModelAvailabilityProvider(),
      lifecycleObserver: ContainerLifecycleObserver()
    )

    var passes = 0
  var runOutputs: [String] = []

    for run in 1...Self.runsPerFixture {
      let result = try await service.diagnose(
        container: fixture.container,
        entries: fixture.entries
      )
      let diagnosis = result.diagnosis
      let rendered = fixture.renderedDigest
      let log = """
        === \(fixture.name) run \(run)/\(Self.runsPerFixture) ===
        DIGEST:
        \(rendered)

        DIAGNOSIS:
        summary: \(diagnosis.summary)
        category: \(diagnosis.category)
        confidence: \(diagnosis.confidence)
        actions: \(diagnosis.suggestedActions.joined(separator: " | "))
        degraded: \(result.wasDegraded)
        TELEMETRY: violations=\(result.telemetry.violationCount) \
        retries=\(result.telemetry.retryCount) degraded=\(result.telemetry.wasDegraded)
        """
      runOutputs.append(log)

      if fixture.validate(diagnosis) {
        passes += 1
      }
    }

    let artifactURL = Self.artifactsDirectory.appendingPathComponent("\(fixture.name).log")
    try runOutputs.joined(separator: "\n\n").write(to: artifactURL, atomically: true, encoding: .utf8)

    #expect(
      passes == Self.runsPerFixture,
      "\(fixture.name): \(passes)/\(Self.runsPerFixture) runs passed — see \(artifactURL.path)"
    )
  }
}

// MARK: - Fixture definitions

struct DiagnosisRegressionFixture: Sendable {
  let name: String
  let logFile: String
  let container: ContainerDetail
  let expectedCategories: Set<FailureCategory>
  let labeledSources: Bool
  let mustNotMention: [String]
  let extraValidation: @Sendable (ContainerDiagnosis) -> Bool

  var entries: [LogEntry] {
    let url = Self.fixturesDirectory.appendingPathComponent(logFile)
    let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    if labeledSources {
      return LabeledFixtureParser.parse(text: text)
    }
    return LogParser().parse(text: text)
  }

  var renderedDigest: String {
    let digest = LogDigestBuilder().build(
      entries: entries,
      context: ContainerContext(
        containerName: container.id,
        image: container.image,
        exitStatus: container.exitStatus,
        restartCount: container.restartCount
      ),
      window: DigestWindow(description: "fixture log window")
    )
    return PromptRenderer().render(digest)
  }

  func validate(_ diagnosis: ContainerDiagnosis) -> Bool {
    guard expectedCategories.contains(diagnosis.category) else { return false }
    guard !diagnosis.summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
    guard !diagnosis.suggestedActions.isEmpty, diagnosis.suggestedActions.count <= 4 else { return false }

    let blob = ([diagnosis.summary] + diagnosis.suggestedActions)
      .joined(separator: " ")
      .lowercased()
    for term in mustNotMention where blob.contains(term.lowercased()) {
      return false
    }

    return extraValidation(diagnosis)
  }

  private static let fixturesDirectory: URL = {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Packages/WharfsideAnalysis/Tests/Fixtures")
  }()

  init(
    name: String,
    logFile: String,
    container: ContainerDetail,
    expectedCategories: Set<FailureCategory>,
    labeledSources: Bool = false,
    mustNotMention: [String] = [],
    extraValidation: @escaping @Sendable (ContainerDiagnosis) -> Bool = { _ in true }
  ) {
    self.name = name
    self.logFile = logFile
    self.container = container
    self.expectedCategories = expectedCategories
    self.labeledSources = labeledSources
    self.mustNotMention = mustNotMention
    self.extraValidation = extraValidation
  }

  static let all: [DiagnosisRegressionFixture] = [
    DiagnosisRegressionFixture(
      name: "postgres_crash",
      logFile: "postgres_crash.log",
      container: ContainerDetail(
        id: "db",
        image: "postgres:16",
        status: .stopped,
        command: ["postgres"],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        startedAt: nil,
        exitStatus: .unavailable(reason: .noEvidence),
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
      ),
      expectedCategories: [.configuration],
      extraValidation: { diagnosis in
        let summary = diagnosis.summary.lowercased()
        let actions = diagnosis.suggestedActions.joined(separator: " ").lowercased()
        let mentionsDisk = summary.contains("disk") || summary.contains("space")
          || actions.contains("disk") || actions.contains("space") || actions.contains("volume")
        let blamesAdmin = summary.contains("administrator command")
          && !summary.contains("disk") && !summary.contains("space")
        return mentionsDisk && !blamesAdmin
      }
    ),
    DiagnosisRegressionFixture(
      name: "node_econnrefused",
      logFile: "node_econnrefused.log",
      container: stoppedContainer(id: "api", image: "node:20"),
      expectedCategories: [.dependencyUnreachable],
      extraValidation: { diagnosis in
        let blob = ([diagnosis.summary] + diagnosis.suggestedActions).joined(separator: " ").lowercased()
        return blob.contains("econnrefused") || blob.contains("connection refused")
          || blob.contains("connect")
      }
    ),
    DiagnosisRegressionFixture(
      name: "oom_kill",
      logFile: "oom_kill.log",
      container: stoppedContainer(id: "worker", image: "app:latest"),
      expectedCategories: [.outOfMemory],
      extraValidation: { _ in true }
    ),
    DiagnosisRegressionFixture(
      name: "silent_exit",
      logFile: "silent_exit.log",
      container: stoppedContainer(id: "quiet", image: "app:1", exitStatus: .known(0, source: .runtime)),
      expectedCategories: [.unknown],
      extraValidation: { diagnosis in
        diagnosis.confidence == .low || diagnosis.confidence == .medium
      }
    ),
    DiagnosisRegressionFixture(
      name: "jvm_stacktrace",
      logFile: "jvm_stacktrace.log",
      container: stoppedContainer(id: "java", image: "app:jvm"),
      expectedCategories: [.applicationBug, .configuration],
      extraValidation: { _ in true }
    ),
    DiagnosisRegressionFixture(
      name: "boot_noise_contamination",
      logFile: "boot_noise_contamination.log",
      container: stoppedContainer(id: "crashy", image: "crashy:latest"),
      expectedCategories: [.configuration],
      labeledSources: true,
      mustNotMention: ["vminitd", "memory threshold", "out of memory", "oom", "insufficient memory"],
      extraValidation: { diagnosis in
        let summary = diagnosis.summary.lowercased()
        let actions = diagnosis.suggestedActions.joined(separator: " ").lowercased()
        return summary.contains("disk") || summary.contains("space")
          || actions.contains("disk") || actions.contains("space")
      }
    ),
    DiagnosisRegressionFixture(
      name: "boot_only_crash",
      logFile: "boot_only_crash.log",
      container: stoppedContainer(id: "init-fail", image: "broken:latest"),
      expectedCategories: [.imageOrRuntime, .configuration, .unknown],
      labeledSources: true
    )
  ]
}

private func stoppedContainer(
  id: String,
  image: String,
  exitStatus: WharfsideAnalysis.ExitStatus = .unavailable(reason: .noEvidence)
) -> ContainerDetail {
  ContainerDetail(
    id: id,
    image: image,
    status: .stopped,
    command: ["app"],
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    startedAt: nil,
    exitStatus: exitStatus,
    restartCount: 0,
    ports: [],
    mounts: [],
    environment: [],
    networks: []
  )
}
#endif
