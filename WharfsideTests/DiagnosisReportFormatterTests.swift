// WharfsideTests/DiagnosisReportFormatterTests.swift
// Issue 1.11 — golden-string coverage for the copyable diagnosis report.

import Foundation
import Testing
import WharfsideAnalysis
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
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16\nLAST_ERROR:\nNo space left on device",
            ruleMetadata: .empty
        )

        let report = DiagnosisReportFormatter.render(
            result: result,
            container: sampleContainer(),
            environment: sampleEnvironment()
        )

        let expected = """
        ## Wharfside diagnosis report
        Wharfside 0.1.1 · container runtime 1.0.0 · macOS 26.0
        Container: db · image: postgres:16 · status: stopped
        Generated: 2023-11-14T22:13:20Z

        ### Digest
        ```
        CONTAINER: db
        IMAGE: postgres:16
        LAST_ERROR:
        No space left on device
        ```

        ### Diagnosis
        Diagnosed by: on-device model over digest
        Summary: PostgreSQL shut down because the host disk is full.
        Category: configuration · Confidence: high
        Suggested actions:
        1. Free disk space on the host, then run `container start db`
        2. Inspect volume usage with `container inspect db`
        Degraded: false · Retries: 0 · Violations: none
        Rulebook: seed (fallback) · Rules fired: none · Skipped unknown rule kinds: none
        """

        #expect(report == expected)
    }

    @Test func rendersDeterministicPrecheckSource() {
        let result = DiagnosisResult(
            diagnosis: ContainerDiagnosis(
                summary: "Container stopped via SIGTERM/SIGKILL (orderly stop).",
                category: .stopped,
                suggestedActions: [
                    "Review boot log with `container logs hello --boot` if you need to confirm the stop path"
                ],
                confidence: .high
            ),
            wasDegraded: false,
            telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
            renderedDigest: "CONTAINER: hello\nFACTS:\nTERMINATION: orderly stop",
            ruleMetadata: DiagnosisRuleMetadata(
                rulebookVersion: "0.1.0",
                rulebookSource: .bundled,
                matchedRuleIDs: ["precheck.stop-escalation", "noise.vminitd-memory-threshold"],
                skippedUnknownKinds: [],
                precheckRuleID: "precheck.stop-escalation"
            ),
            source: .deterministicPrecheck(ruleID: "precheck.stop-escalation")
        )

        let report = DiagnosisReportFormatter.render(
            result: result,
            container: sampleContainer(id: "hello", image: "docker.io/library/alpine:latest"),
            environment: sampleEnvironment()
        )

        let diagnosedBy = "### Diagnosis\nDiagnosed by: deterministic precheck "
            + "(precheck.stop-escalation; model not invoked)"
        #expect(report.contains(diagnosedBy))
        #expect(report.contains("Rules fired: precheck.stop-escalation, noise.vminitd-memory-threshold"))
        #expect(!report.contains("what the model said"))
        #expect(!report.contains("Rules matched:"))
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
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16\n\nCORRECTION: The term \"disk\" does not appear.",
            ruleMetadata: .empty
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
            renderedDigest: "CONTAINER: quiet\nIMAGE: app:1\nEXIT_CODE: 0",
            ruleMetadata: .empty
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
            renderedDigest: "CONTAINER: db\nIMAGE: postgres:16",
            ruleMetadata: .empty
        )
        let container = sampleContainer()
        let environment = sampleEnvironment()

        let first = DiagnosisReportFormatter.render(result: result, container: container, environment: environment)
        let second = DiagnosisReportFormatter.render(result: result, container: container, environment: environment)

        #expect(first == second)
    }

    @Test func unknownRuntimeVersionFallsBackToUnknown() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: nil, generatedAt: .now)
        #expect(environment.runtimeVersionLabel == DiagnosisReportEnvironment.unknownVersion)
    }

    @Test func emptyRuntimeVersionFallsBackToUnknown() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: "", generatedAt: .now)
        #expect(environment.runtimeVersionLabel == DiagnosisReportEnvironment.unknownVersion)
    }

    @Test func presentRuntimeVersionWithoutCommitUsesSemverOnly() {
        let environment = DiagnosisReportEnvironment.current(runtimeVersion: "1.0.0", generatedAt: .now)
        #expect(environment.runtimeVersionLabel == "1.0.0")
    }

    @Test func runtimeVersionIncludesShortCommitWhenPresent() {
        let label = DiagnosisReportEnvironment.formatRuntimeLabel(
            version: "apiserver 1.0.0 build 42",
            commit: "ee848e3abc123"
        )
        #expect(label == "1.0.0 (commit ee848e3)")
    }

    @Test func nonHexCommitOmitsParenthetical() {
        // Regression: daemon 1.1.0 reported no commit; the placeholder "unspecified"
        // short-hashed to "unspeci" and leaked into the footer as "(commit unspeci)".
        let label = DiagnosisReportEnvironment.formatRuntimeLabel(
            version: "1.1.0",
            commit: "unspecified"
        )
        #expect(label == "1.1.0")
    }

    /// Digest16 — hello / report2 precheck path golden (formatter acceptance).
    @Test func digest16PrecheckGoldenReportContract() {
        let report = DiagnosisReportFormatter.render(
            result: digest16GoldenResult(),
            container: sampleContainer(id: "hello", image: "docker.io/library/alpine:latest"),
            environment: digestGoldenEnvironment()
        )
        #expect(report == goldenFixture("Digest16.report.md"))
        #expect(!report.localizedCaseInsensitiveContains("memory threshold exceeded"))
        #expect(!report.contains("[10x]"))
    }

    /// Digest15 — crashy / model path golden (structural; no live model).
    @Test func digest15ModelPathGoldenReportContract() {
        let report = DiagnosisReportFormatter.render(
            result: digest15GoldenResult(),
            container: sampleContainer(id: "crashy", image: "crashy:latest"),
            environment: digestGoldenEnvironment()
        )
        #expect(report == goldenFixture("Digest15.report.md"))
        #expect(report.contains("Diagnosed by: on-device model over digest"))
        #expect(report.contains("Rules fired: none"))
        #expect(!report.contains("noise.vminitd-memory-threshold"))
        #expect(!report.contains("precheck.stop-escalation"))
    }

    /// Digest17 — diag-crash / no-evidence precheck path golden (formatter acceptance).
    @Test func digest17NoEvidenceGoldenReportContract() {
        let report = DiagnosisReportFormatter.render(
            result: digest17GoldenResult(),
            container: sampleContainer(id: "diag-crush", image: "docker.io/library/alpine:latest"),
            environment: digestGoldenEnvironment()
        )
        #expect(report == goldenFixture("Digest17.report.md"))
        #expect(report.contains("Diagnosed by: deterministic precheck (precheck.no-evidence; model not invoked)"))
        #expect(report.contains("Category: unknown · Confidence: low"))
        #expect(report.contains("(status 1)"))
        #expect(report.contains("Rules fired: precheck.no-evidence, noise.vminitd-memory-threshold"))
        #expect(!report.contains("precheck.stop-escalation"))
    }

    /// Digest18 — diag-loud / stdio-primary with canonical boot evidence (B8.2).
    /// Digest15/16/17 stay byte-identical; this is the expected stdio-primary golden churn.
    @Test func digest18StdioPrimaryBootEvidenceGoldenReportContract() {
        let report = DiagnosisReportFormatter.render(
            result: digest18GoldenResult(),
            container: sampleContainer(id: "diag-loud", image: "docker.io/library/alpine:latest"),
            environment: digestGoldenEnvironment()
        )
        #expect(report == goldenFixture("Digest18.report.md"))
        #expect(report.contains("EXIT_CODE: 1 (from boot log)"))
        #expect(report.contains("BOOT_LOG (runtime init, usually not the app's crash cause):"))
        #expect(report.contains("Rules fired: noise.vminitd-memory-threshold"))
        #expect(!report.contains("precheck.no-evidence"))
        #expect(report.contains("Diagnosed by: on-device model over digest"))
    }
}

private func digestGoldenEnvironment() -> DiagnosisReportEnvironment {
    DiagnosisReportEnvironment(
        wharfsideVersion: "0.1.1",
        runtimeVersionLabel: "1.0.0 (commit ee848e3)",
        macOSVersion: "26.5.2",
        generatedAt: Date(timeIntervalSince1970: 1_783_576_497) // 2026-07-09T05:54:57Z
    )
}

private func digest16GoldenResult() -> DiagnosisResult {
    let digest = """
        CONTAINER: hello
        IMAGE: docker.io/library/alpine:latest
        EXIT_CODE: 137 (from boot log)
        WINDOW: logs before container exit
        RESTARTS: 0
        SOURCE: boot log only (no application output)
        FACTS:
        TERMINATION: container stopped via SIGTERM then SIGKILL (orderly stop, exit 137)
        COUNTS: INFO=27 UNKNOWN=49 WARN=4
        LAST_LINES:
        2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109
        2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109
        2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit
        """
    return DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "Container stopped via SIGTERM/SIGKILL (orderly stop); "
                + "boot log shows signal 15 → grace period → signal 9 → exit 137.",
            category: .stopped,
            suggestedActions: [
                "Review boot log with `container logs hello --boot` if you need to confirm the stop path"
            ],
            confidence: .high
        ),
        wasDegraded: false,
        telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
        renderedDigest: digest,
        ruleMetadata: DiagnosisRuleMetadata(
            rulebookVersion: "0.1.0",
            rulebookSource: .bundled,
            matchedRuleIDs: ["precheck.stop-escalation", "noise.vminitd-memory-threshold"],
            skippedUnknownKinds: [],
            precheckRuleID: "precheck.stop-escalation"
        ),
        source: .deterministicPrecheck(ruleID: "precheck.stop-escalation")
    )
}

private func digest15GoldenResult() -> DiagnosisResult {
    let digest = """
        CONTAINER: crashy
        IMAGE: crashy:latest
        EXIT_CODE: 1
        WINDOW: logs before container exit
        RESTARTS: 0
        COUNTS: ERROR=1 UNKNOWN=1
        FIRST_ERROR:
        ERROR: No space left on device
        LAST_ERROR:
        ERROR: No space left on device
        LAST_LINES:
        head: invalid number '10M'
        ERROR: No space left on device
        """
    return DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "The container failed because the disk is full — writes returned "
                + "\"No space left on device\".",
            category: .configuration,
            suggestedActions: [
                "Free disk space on the host, then run `container start crashy`",
                "Inspect volume usage with `container inspect crashy`"
            ],
            confidence: .medium
        ),
        wasDegraded: false,
        telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
        renderedDigest: digest,
        ruleMetadata: DiagnosisRuleMetadata(
            rulebookVersion: "0.1.0",
            rulebookSource: .bundled,
            matchedRuleIDs: [],
            skippedUnknownKinds: [],
            precheckRuleID: nil
        ),
        source: .onDeviceModel
    )
}

private func digest17GoldenResult() -> DiagnosisResult {
    let digest = """
        CONTAINER: diag-crush
        IMAGE: docker.io/library/alpine:latest
        EXIT_CODE: 1 (from boot log)
        WINDOW: logs before container exit
        RESTARTS: 0
        SOURCE: boot log only (no application output)
        FACTS:
        EVIDENCE: container exited without writing any application output
        COUNTS: INFO=17 UNKNOWN=45 WARN=4
        LAST_LINES:
        2026-07-16T07:49:10.876Z info vminitd: id: diag-crush, pid: 109 started managed process
        2026-07-16T07:49:10.877Z info vminitd: id: diag-crush, status: 1 managed process exit
        2026-07-16T07:49:10.877Z info vminitd: id: diag-crush closing relay for StandardIO stdout
        2026-07-16T07:49:10.877Z info vminitd: id: diag-crush closing relay for StandardIO stderr
        [    0.502572] EXT4-fs (vdb): unmounting filesystem aa598811-9809-4d4d-9c06-5de0b5962e0c.
        """
    return DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "The container exited (status 1) without writing any application output — "
                + "there is nothing in the logs to analyze. If this exit is unexpected, "
                + "check whether the command writes errors to stdout/stderr.",
            category: .unknown,
            suggestedActions: [
                "Run `container logs diag-crush` to confirm no output was produced",
                "If unexpected, run the container's command manually to see its error output"
            ],
            confidence: .low
        ),
        wasDegraded: false,
        telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
        renderedDigest: digest,
        ruleMetadata: DiagnosisRuleMetadata(
            rulebookVersion: "0.1.0",
            rulebookSource: .bundled,
            matchedRuleIDs: ["precheck.no-evidence", "noise.vminitd-memory-threshold"],
            skippedUnknownKinds: [],
            precheckRuleID: "precheck.no-evidence"
        ),
        source: .deterministicPrecheck(ruleID: "precheck.no-evidence")
    )
}

private func digest18GoldenResult() -> DiagnosisResult {
    let digest = """
        CONTAINER: diag-loud
        IMAGE: docker.io/library/alpine:latest
        EXIT_CODE: 1 (from boot log)
        WINDOW: logs before container exit
        RESTARTS: 0
        COUNTS: ERROR=1
        FIRST_ERROR:
        ERROR boom
        LAST_ERROR:
        ERROR boom
        TOP_PATTERNS:
        1. [1x] boom (first=1970-01-01T00:00:00Z, last=1970-01-01T00:00:00Z)
        LAST_LINES:
        ERROR boom
        BOOT_LOG (runtime init, usually not the app's crash cause):
        2026-07-16T12:47:10.870Z info vminitd: id: diag-loud, pid: 109 got back pid data
        2026-07-16T12:47:10.876Z info vminitd: id: diag-loud, pid: 109 started managed process
        2026-07-16T12:47:10.877Z info vminitd: id: diag-loud, status: 1 managed process exit
        2026-07-16T12:47:10.877Z info vminitd: id: diag-loud closing relay for StandardIO stdout
        2026-07-16T12:47:10.877Z info vminitd: id: diag-loud closing relay for StandardIO stderr
        """
    return DiagnosisResult(
        diagnosis: ContainerDiagnosis(
            summary: "Application printed an error before exit.",
            category: .applicationBug,
            suggestedActions: ["Inspect the application command"],
            confidence: .medium
        ),
        wasDegraded: false,
        telemetry: DiagnosisTelemetry(violations: [], retryCount: 0, wasDegraded: false),
        renderedDigest: digest,
        ruleMetadata: DiagnosisRuleMetadata(
            rulebookVersion: "0.1.0",
            rulebookSource: .bundled,
            matchedRuleIDs: ["noise.vminitd-memory-threshold"],
            skippedUnknownKinds: [],
            precheckRuleID: nil
        ),
        source: .onDeviceModel
    )
}

private func goldenFixture(_ name: String) -> String {
    let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/Goldens/\(name)")
    return (try? String(contentsOf: url, encoding: .utf8))?
        .trimmingCharacters(in: CharacterSet(charactersIn: "\n"))
        ?? ""
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
        exitStatus: .known(1, source: .runtime),
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
    )
}

private func sampleEnvironment() -> DiagnosisReportEnvironment {
    DiagnosisReportEnvironment(
        wharfsideVersion: "0.1.1",
        runtimeVersionLabel: "1.0.0",
        macOSVersion: "26.0",
        generatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
