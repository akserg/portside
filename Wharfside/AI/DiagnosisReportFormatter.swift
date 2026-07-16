// AI/DiagnosisReportFormatter.swift
// Issue 1.11 — renders a copyable "diagnosis report" bundle (digest + diagnosis +
// telemetry + versions) so a wrong-diagnosis report carries what the model actually saw.

import Foundation

/// Version metadata attached to a diagnosis report. Built once per copy, never blocking:
/// callers pass whatever is already cached (see `AppState.diagnosisReportEnvironment`).
struct DiagnosisReportEnvironment: Sendable, Equatable {
    nonisolated static let unknownVersion = "unknown"

    let wharfsideVersion: String
    /// e.g. `1.0.0 (commit ee848e3)` from cached `SystemHealth`.
    let runtimeVersionLabel: String
    let macOSVersion: String
    let generatedAt: Date

    /// Builds the environment from live process/bundle info plus cached runtime metadata.
    nonisolated static func current(
        runtimeVersion: String?,
        runtimeCommit: String? = nil,
        generatedAt: Date = .now
    ) -> DiagnosisReportEnvironment {
        DiagnosisReportEnvironment(
            wharfsideVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? unknownVersion,
            runtimeVersionLabel: formatRuntimeLabel(version: runtimeVersion, commit: runtimeCommit),
            macOSVersion: macOSVersionString(),
            generatedAt: generatedAt
        )
    }

    nonisolated static func formatRuntimeLabel(version: String?, commit: String?) -> String {
        guard let version, !version.isEmpty else { return unknownVersion }
        let semver = extractSemver(from: version)
        // Omit the parenthetical when the daemon reports no commit or a non-hex
        // placeholder (e.g. "unspecified", which otherwise short-hashes to "unspeci").
        guard let commit, isHexCommit(commit) else { return semver }
        let shortCommit = String(commit.prefix(7))
        return "\(semver) (commit \(shortCommit))"
    }

    nonisolated private static func isHexCommit(_ commit: String) -> Bool {
        !commit.isEmpty && commit.allSatisfy(\.isHexDigit)
    }

    nonisolated private static func extractSemver(from versionString: String) -> String {
        let pattern = #/(\d+\.\d+\.\d+)/#
        if let match = versionString.firstMatch(of: pattern) {
            return String(match.1)
        }
        return versionString
    }

    nonisolated private static func macOSVersionString() -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        guard version.patchVersion != 0 else {
            return "\(version.majorVersion).\(version.minorVersion)"
        }
        return "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)"
    }
}

/// Pure function: `(DiagnosisResult, ContainerDetail, DiagnosisReportEnvironment) -> String`.
/// Deterministic for a given input — no locale-, timezone-, or ordering-dependent output.
enum DiagnosisReportFormatter {
    nonisolated static func render(
        result: DiagnosisResult,
        container: ContainerDetail,
        environment: DiagnosisReportEnvironment
    ) -> String {
        var lines: [String] = []
        lines.append("## Wharfside diagnosis report")
        lines.append(
            "Wharfside \(environment.wharfsideVersion) · "
            + "container runtime \(environment.runtimeVersionLabel) · "
            + "macOS \(environment.macOSVersion)"
        )
        lines.append(
            "Container: \(container.id) · image: \(container.image) · status: \(container.status.rawValue)"
        )
        lines.append("Generated: \(isoTimestamp(environment.generatedAt))")
        lines.append("")
        lines.append("### Digest")
        lines.append("```")
        lines.append(result.renderedDigest)
        lines.append("```")
        lines.append("")
        lines.append("### Diagnosis")
        lines.append(result.source.reportLine)
        lines.append("Summary: \(result.diagnosis.summary)")
        lines.append(
            "Category: \(result.diagnosis.category.rawValue) · Confidence: \(result.diagnosis.confidence.rawValue)"
        )
        lines.append("Suggested actions:")
        if result.diagnosis.suggestedActions.isEmpty {
            lines.append("(none)")
        } else {
            for (index, action) in result.diagnosis.suggestedActions.enumerated() {
                lines.append("\(index + 1). \(action)")
            }
        }
        lines.append(
            "Degraded: \(result.wasDegraded) · Retries: \(result.telemetry.retryCount) · "
            + "Violations: \(violationsSummary(result.telemetry.violations))"
        )
        lines.append(
            DiagnosisRuleMetadata.formatFooterLine(
                rulebookVersion: result.ruleMetadata.rulebookVersion,
                rulebookSource: result.ruleMetadata.rulebookSource,
                fallbackReason: result.ruleMetadata.fallbackReason,
                matchedRuleIDs: result.ruleMetadata.matchedRuleIDs,
                skippedUnknownKinds: result.ruleMetadata.skippedUnknownKinds
            )
        )
        return lines.joined(separator: "\n")
    }

    nonisolated private static func violationsSummary(_ violations: [DiagnosisViolation]) -> String {
        guard !violations.isEmpty else { return "none" }
        return violations.map(describe).joined(separator: "; ")
    }

    nonisolated private static func describe(_ violation: DiagnosisViolation) -> String {
        switch violation {
        case .unknownDespiteErrors(let errorCount):
            return "unknownDespiteErrors(\(errorCount))"
        case .categoryWithoutEvidence(let category):
            return "categoryWithoutEvidence(\(category.rawValue))"
        case .suppressedCategory(let category):
            return "suppressedCategory(\(category.rawValue))"
        case .fabricatedEvidence(let term):
            return "fabricatedEvidence(\(term))"
        case .wrongCLIVocabulary(let action):
            return "wrongCLIVocabulary(\(action))"
        }
    }

    nonisolated private static func isoTimestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}
