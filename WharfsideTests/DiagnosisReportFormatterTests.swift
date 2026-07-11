// WharfsideTests/DiagnosisReportFormatterTests.swift
// Issue 1.11 — golden-string coverage for the copyable diagnosis report.

import Foundation
import Testing
@testable import Wharfside

@Suite
struct DiagnosisReportFormatterTests {
    @Test func rendersNormalResult() {
        let result = DiagnosisResult(
            diagnosis: ContainerDiagnosis(
                summary: "PostgreSQL shut down because the host disk is full.",
                category: .configuration,
                suggestedActions: [
                    "Free disk space on the host, then run `container start db`",
                    "Inspect volume usage with `container inspect db`"
                ],
                confidence: .high
            ),
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16\nLAST_ERROR:\nNo space left on device"
        )

        let report = DiagnosisReportFormatter.render(
            result: result,
            container: sampleContainer(),
            environment: sampleEnvironment()
        )

        let expected = """
        ## Wharfside diagnosis report
        Wharfside 1.0 · container runtime 1.0.0 · macOS 26.0
        Container: db · image: postgres:16 · status: stopped
        Generated: 2023-11-14T22:13:20Z

        ### Digest (what the model saw)
        ```
        CONTAINER: db
        IMAGE: postgres:16
        LAST_ERROR:
        No space left on device
        ```

        ### Diagnosis (what the model said)
        Summary: PostgreSQL shut down because the host disk is full.
        Category: configuration · Confidence: high
        Suggested actions:
        1. Free disk space on the host, then run `container start db`
        2. Inspect volume usage with `container inspect db`
        Degraded: false · Retries: 0 · Violations: none
        """

        #expect(report == expected)
    }

    @Test func rendersDegradedRetriedResultWithViolations() {
        let result = DiagnosisResult(
            diagnosis: ContainerDiagnosis(
                summary: "Logs show 3 ERROR/WARN line(s); automated diagnosis was inconclusive.",
                category: .unknown,
                suggestedActions: ["Review container logs with `container logs db`"],
                confidence: .low
            ),
            wasDegraded: true,
            telemetry: DiagnosisTelemetry(
                violations: [
                    .fabricatedEvidence(term: "disk"),
                    .unknownDespiteErrors(errorCount: 3)
                ],
                retryCount: 1,
                wasDegraded: true
            ),
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16\n\nCORRECTION: The term \"disk\" does not appear."
        )

        let report = DiagnosisReportFormatter.render(
            result: result,
            container: sampleContainer(),
            environment: sampleEnvironment()
        )

        let violationsLine = "Degraded: true · Retries: 1 · Violations: "
            + "fabricatedEvidence(disk); unknownDespiteErrors(3)"
        #expect(report.contains(violationsLine))
        #expect(report.contains("CORRECTION: The term \"disk\" does not appear."))
    }

    @Test func rendersNoSuggestedActionsAsNone() {
        let result = DiagnosisResult(
            diagnosis: ContainerDiagnosis(
                summary: "Clean exit, no evidence of a failure.",
                category: .unknown,
                suggestedActions: [],
                confidence: .low
            ),
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
            renderedDigest: "CONTAINER: quiet\nIMAGE: app:1\nEXIT_CODE: 0"
        )

        let report = DiagnosisReportFormatter.render(
            result: result,
            container: sampleContainer(id: "quiet", image: "app:1", status: .stopped),
            environment: sampleEnvironment()
        )

        #expect(report.contains("Suggested actions:\n(none)"))
    }

    @Test func isDeterministicForTheSameInput() {
        let result = DiagnosisResult(
            diagnosis: ContainerDiagnosis(
                summary: "Deterministic summary.",
                category: .configuration,
                suggestedActions: ["Do the thing"],
                confidence: .medium
            ),
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16"
        )
        let container = sampleContainer()
        let environment = sampleEnvironment()

        let first = DiagnosisReportFormatter.render(result: result, container: container, environment: environment)
        let second = DiagnosisReportFormatter.render(result: result, container: container, environment: environment)

        #expect(first == second)
    }

    @Test func unknownRuntimeVersionFallsBackToUnknown() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: nil, generatedAt: .now)
        #expect(environment.runtimeVersion == DiagnosisReportEnvironment.unknownVersion)
    }

    @Test func emptyRuntimeVersionFallsBackToUnknown() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: "", generatedAt: .now)
        #expect(environment.runtimeVersion == DiagnosisReportEnvironment.unknownVersion)
    }

    @Test func presentRuntimeVersionIsUsedVerbatim() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: "1.0.0", generatedAt: .now)
        #expect(environment.runtimeVersion == "1.0.0")
    }
}

private func sampleContainer(
    id: String = "db",
    image: String = "postgres:16",
    status: ContainerRuntimeStatus = .stopped
) -> ContainerDetail {
    ContainerDetail(
        id: id,
        image: image,
        status: status,
        command: ["postgres"],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        startedAt: nil,
        exitCode: 1,
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
    )
}

private func sampleEnvironment() -> DiagnosisReportEnvironment {
    DiagnosisReportEnvironment(
        wharfsideVersion: "1.0",
        runtimeVersion: "1.0.0",
        macOSVersion: "26.0",
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
