// WharfsideTests/LogDiagnosisServiceReport2Tests.swift
// B4 — report2 / hello flagship (deterministic tier). Model never invoked.
// Digest16 golden contract: threshold demoted from LAST_LINES, both rules fired,
// INFO collapsed to final cycle, SIGTERM→SIGKILL→137 present.
// Live-model crashy synthesis stays in DiagnosisRegressionTests (nightly-gated).

import Foundation
import Testing
import WharfsideAnalysis
@testable import Wharfside

@MainActor
@Suite struct LogDiagnosisServiceReport2Tests {
  @Test func report2PrecheckShortCircuitsModelWithOrderlyStop() async throws {
    let session = StubDiagnosisSession(mode: .emit(oomMisdiagnosis))
    let service = makeReport2Service(
      session: session,
      exitStatus: .unavailable(reason: .runtimeGone)
    )
    let entries = try LabeledFixtureParser.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let container = sampleDetail(
      id: "hello",
      image: "docker.io/library/alpine:latest",
      exitStatus: .unavailable(reason: .noEvidence)
    )
    let result = try await service.diagnose(container: container, entries: entries)

    #expect(session.streamCallCount == 0)
    #expect(result.diagnosis.category == .stopped)
    #expect(result.diagnosis.summary.contains("SIGTERM/SIGKILL"))
    #expect(result.source == .deterministicPrecheck(ruleID: "precheck.stop-escalation"))
    #expect(result.ruleMetadata.matchedRuleIDs.contains("precheck.stop-escalation"))
    #expect(result.ruleMetadata.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(!result.ruleMetadata.matchedRuleIDs.contains("validator.oom-needs-kernel-evidence"))
    #expect(!result.ruleMetadata.matchedRuleIDs.contains("prompt.exit-137-stop-hint"))
    #expect(result.ruleMetadata.precheckRuleID == "precheck.stop-escalation")
    #expect(result.ruleMetadata.rulebookSource == .bundled)
    #expect(result.ruleMetadata.fallbackReason == nil)
    #expect(!result.wasDegraded)
    assertDigest16RenderedDigest(result.renderedDigest)
    assertDigest16FormattedReport(result: result, container: container)
  }

  /// Malformed bundled bytes → seed fallback; diagnosis still succeeds (I4/I6 through app path).
  @Test func malformedRulebookFallsBackAndReport2StillShortCircuits() async throws {
    let pipeline = RulebookPipeline.load(rulebookData: Data("not json".utf8))
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)

    let session = StubDiagnosisSession(mode: .emit(oomMisdiagnosis))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      containerService: ExitStatusStubContainerService(exitStatus: .unavailable(reason: .runtimeGone)),
      sessionFactory: session,
      rulebookPipeline: pipeline
    )

    let entries = try LabeledFixtureParser.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let result = try await service.diagnose(
      container: sampleDetail(id: "hello", image: "docker.io/library/alpine:latest"),
      entries: entries
    )

    #expect(session.streamCallCount == 0)
    #expect(result.ruleMetadata.rulebookSource == .fallback)
    #expect(result.ruleMetadata.fallbackReason == .signatureInvalid)
    #expect(result.diagnosis.category == .stopped)
    #expect(result.ruleMetadata.matchedRuleIDs.contains("precheck.stop-escalation"))
    #expect(result.ruleMetadata.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(result.ruleMetadata.footerLine.contains("seed (bundled rulebook rejected: signature)"))
  }

  /// Bit-flipped bundled document with real detached signature → seed fallback (B4a / I4).
  @Test func tamperedBundledRulebookFallsBackToSeedAndReport2StillShortCircuits() async throws {
    let documentURL = try #require(
      Bundle.main.url(forResource: "Rulebook", withExtension: "json")
    )
    let signatureURL = try #require(
      Bundle.main.url(forResource: "Rulebook.json", withExtension: "sig")
    )
    var tampered = try Data(contentsOf: documentURL)
    tampered[tampered.startIndex] ^= 0x01
    let pipeline = RulebookPipeline.load(
      rulebookData: tampered,
      signatureData: try Data(contentsOf: signatureURL)
    )
    #expect(pipeline.fallbackReason == .signatureInvalid)

    let session = StubDiagnosisSession(mode: .emit(oomMisdiagnosis))
    let service = LogDiagnosisService(
      availability: StubProvider(sequence: [.full]),
      lifecycleObserver: ContainerLifecycleObserver(),
      containerService: ExitStatusStubContainerService(exitStatus: .unavailable(reason: .runtimeGone)),
      sessionFactory: session,
      rulebookPipeline: pipeline
    )

    let entries = try LabeledFixtureParser.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let result = try await service.diagnose(
      container: sampleDetail(id: "hello", image: "docker.io/library/alpine:latest"),
      entries: entries
    )

    #expect(session.streamCallCount == 0)
    #expect(result.ruleMetadata.rulebookSource == .fallback)
    #expect(result.ruleMetadata.fallbackReason == .signatureInvalid)
    #expect(result.diagnosis.category == .stopped)
    #expect(result.ruleMetadata.matchedRuleIDs.contains("precheck.stop-escalation"))
    #expect(result.ruleMetadata.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(result.ruleMetadata.footerLine.contains("rejected: signature"))
  }

  /// Explicit unavailable exit (ambiguous) fails closed — no exit-code precheck (I6).
  @Test func unavailableExitDoesNotFireStopPrecheck() async throws {
    let session = StubDiagnosisSession(mode: .emit(
      ContainerDiagnosis(
        summary: "Inconclusive without exit evidence.",
        category: .unknown,
        suggestedActions: ["Inspect boot log"],
        confidence: .low
      )
    ))
    let service = makeReport2Service(
      session: session,
      exitStatus: .unavailable(reason: .ambiguousEvidence)
    )
    let entries = try LabeledFixtureParser.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let result = try await service.diagnose(
      container: sampleDetail(id: "hello", image: "docker.io/library/alpine:latest"),
      entries: entries
    )

    #expect(session.streamCallCount >= 1)
    #expect(result.source == .onDeviceModel)
    #expect(result.ruleMetadata.precheckRuleID == nil)
    #expect(!result.ruleMetadata.matchedRuleIDs.contains("precheck.stop-escalation"))
    #expect(!result.renderedDigest.contains("EXIT_CODE:"))
  }
}

@MainActor
private let oomMisdiagnosis = ContainerDiagnosis(
  summary: "The container exited due to a memory threshold exceeded by vminitd.",
  category: .outOfMemory,
  suggestedActions: ["Increase memory limit"],
  confidence: .medium
)

@MainActor
private func makeReport2Service(
  session: StubDiagnosisSession,
  exitStatus: WharfsideAnalysis.ExitStatus
) -> LogDiagnosisService {
  LogDiagnosisService(
    availability: StubProvider(sequence: [.full]),
    lifecycleObserver: ContainerLifecycleObserver(),
    containerService: ExitStatusStubContainerService(exitStatus: exitStatus),
    sessionFactory: session
  )
}

private func assertDigest16RenderedDigest(_ rendered: String) {
  #expect(rendered.contains("EXIT_CODE: 137 (from boot log)"))
  #expect(rendered.contains("FACTS:"))
  #expect(rendered.contains("orderly stop"))
  #expect(rendered.contains("COUNTS: INFO=27"))
  #expect(rendered.contains("sending signal 15 to process"))
  #expect(rendered.contains("sending signal 9 to process"))
  #expect(rendered.contains("status: 137 managed process exit"))
  #expect(!rendered.localizedCaseInsensitiveContains("memory threshold exceeded"))
  #expect(!rendered.contains("[10x]"))
}

@MainActor
private func assertDigest16FormattedReport(result: DiagnosisResult, container: ContainerDetail) {
  let report = DiagnosisReportFormatter.render(
    result: result,
    container: container,
    environment: DiagnosisReportEnvironment(
      wharfsideVersion: "0.1.1",
      runtimeVersionLabel: "1.0.0 (commit ee848e3)",
      macOSVersion: "26.5.2",
      generatedAt: Date(timeIntervalSince1970: 1_783_576_497) // 2026-07-09T05:54:57Z
    )
  )
  #expect(report.contains("Wharfside 0.1.1"))
  #expect(report.contains("### Diagnosis"))
  let diagnosedBy = "Diagnosed by: deterministic precheck (precheck.stop-escalation; model not invoked)"
  #expect(report.contains(diagnosedBy))
  #expect(!report.contains("what the model said"))
  #expect(report.contains("Rules fired: precheck.stop-escalation, noise.vminitd-memory-threshold"))
  #expect(!report.contains("validator.oom-needs-kernel-evidence"))
  #expect(report.contains("Rules fired:") && !report.contains("Rules matched:"))
}
