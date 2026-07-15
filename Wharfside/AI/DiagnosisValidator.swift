// AI/DiagnosisValidator.swift
// Issue 1.6.1 — deterministic post-checks on model diagnosis output.

import Foundation
import RulebookCore
import WharfsideAnalysis

enum DiagnosisViolation: Equatable, Sendable {
    case unknownDespiteErrors(errorCount: Int)
    case categoryWithoutEvidence(category: FailureCategory)
    case suppressedCategory(category: FailureCategory)
    case fabricatedEvidence(term: String)
    case wrongCLIVocabulary(action: String)
}

struct DiagnosisTelemetry: Sendable, Equatable {
    var violations: [DiagnosisViolation]
    var retryCount: Int
    var wasDegraded: Bool

    var violationCount: Int { violations.count }
}

/// Where the final diagnosis came from — report copy must not attribute prechecks to the model.
enum DiagnosisSource: Sendable, Equatable {
    /// Deterministic precheck short-circuited; FoundationModels was not invoked.
    case deterministicPrecheck(ruleID: String)
    /// On-device model synthesized over the digest (possibly after retries/degrade).
    case onDeviceModel

    nonisolated var reportLine: String {
        switch self {
        case .deterministicPrecheck(let ruleID):
            return "Diagnosed by: deterministic precheck (\(ruleID); model not invoked)"
        case .onDeviceModel:
            return "Diagnosed by: on-device model over digest"
        }
    }
}

struct DiagnosisResult: Sendable, Equatable {
    let diagnosis: ContainerDiagnosis
    nonisolated let wasDegraded: Bool
    nonisolated let telemetry: DiagnosisTelemetry
    nonisolated let renderedDigest: String
    nonisolated let ruleMetadata: DiagnosisRuleMetadata
    nonisolated let source: DiagnosisSource
    /// Exit status resolved for the digest (runtime and/or boot log). Used by B6 Overview backfill.
    nonisolated let exitStatus: ExitStatus

    nonisolated init(
        diagnosis: ContainerDiagnosis,
        wasDegraded: Bool,
        telemetry: DiagnosisTelemetry,
        renderedDigest: String,
        ruleMetadata: DiagnosisRuleMetadata,
        source: DiagnosisSource = .onDeviceModel,
        exitStatus: ExitStatus = .unavailable(reason: .noEvidence)
    ) {
        self.diagnosis = diagnosis
        self.wasDegraded = wasDegraded
        self.telemetry = telemetry
        self.renderedDigest = renderedDigest
        self.ruleMetadata = ruleMetadata
        self.source = source
        self.exitStatus = exitStatus
    }
}

struct DiagnosisValidator: Sendable {
    private static let evidenceTermGroups: [[String]] = [
        ["stack overflow"],
        ["out of memory", "outofmemory", "heap space"],
        ["no space left", "disk full"],
        ["connection refused", "econnrefused"],
        ["segfault"],
        ["killed"],
        ["oom"],
        ["administrator command"]
    ]

    /// Flat list used for scanning summaries; each group is satisfied if any synonym appears in the digest.
    private static let evidenceTerms: [String] = evidenceTermGroups.flatMap { $0 }

    private static let oomSignals: [String] = [
        "killed",
        "oom",
        "out of memory",
        "heap space"
    ]

    func validate(
        _ diagnosis: ContainerDiagnosis,
        against digest: LogDigest,
        renderedDigest: String,
        evaluation: RuleEvaluation = .empty,
        matchLines: [String] = []
    ) -> [DiagnosisViolation] {
        var violations: [DiagnosisViolation] = []

        if evaluation.suppressedCategories.contains(diagnosis.category.rawValue) {
            violations.append(.suppressedCategory(category: diagnosis.category))
        }

        if let requirements = evaluation.evidenceRequirements[diagnosis.category.rawValue] {
            let lines = matchLines.isEmpty ? digestEvidenceLines(digest) : matchLines
            let satisfied = requirements.contains { rule in
                rule.requiredEvidence.contains { pattern in
                    RuleEngine.anyLineMatches(pattern, lines: lines)
                }
            }
            if !satisfied {
                violations.append(.categoryWithoutEvidence(category: diagnosis.category))
            }
        }

        let errorCount = Self.signalCount(in: digest)
        if errorCount > 0, diagnosis.category == .unknown {
            violations.append(.unknownDespiteErrors(errorCount: errorCount))
        }
        if errorCount == 0, !Self.hasOOMSignal(in: digest), diagnosis.category != .unknown {
            violations.append(.categoryWithoutEvidence(category: diagnosis.category))
        }

        let digestLower = renderedDigest.lowercased()
        let summaryLower = diagnosis.summary.lowercased()
        for group in Self.evidenceTermGroups {
            guard group.contains(where: { summaryLower.contains($0) }) else { continue }
            let supported = group.contains { digestLower.contains($0) }
            if !supported {
                let term = group.first { summaryLower.contains($0) } ?? group[0]
                violations.append(.fabricatedEvidence(term: term))
            }
        }

        for action in diagnosis.suggestedActions {
            let lower = action.lowercased()
            if lower.contains("docker-compose") || lower.contains("docker compose") || lower.contains("docker") {
                violations.append(.wrongCLIVocabulary(action: action))
            }
        }

        return violations
    }

    /// Repairs `docker` vocabulary in place. Returns whether any action changed.
    @discardableResult
    mutating func repairVocabulary(_ diagnosis: inout ContainerDiagnosis) -> Bool {
        var changed = false
        var repaired: [String] = []

        for action in diagnosis.suggestedActions {
            if let fixed = Self.repairDockerAction(action) {
                repaired.append(fixed)
                if fixed != action {
                    changed = true
                }
            } else {
                changed = true
            }
        }

        diagnosis.suggestedActions = repaired
        return changed
    }

    func degrade(
        diagnosis: ContainerDiagnosis,
        digest: LogDigest,
        violations: [DiagnosisViolation]
    ) -> ContainerDiagnosis {
        let category = Self.degradedCategory(
            modelCategory: diagnosis.category,
            digest: digest,
            violations: violations
        )
        return ContainerDiagnosis(
            summary: Self.factSummary(for: digest),
            category: category,
            suggestedActions: diagnosis.suggestedActions.isEmpty
                ? ["Review container logs with `container logs \(digest.containerName)`"]
                : diagnosis.suggestedActions,
            confidence: .low
        )
    }

    func correctionLines(for violations: [DiagnosisViolation], digest: LogDigest) -> [String] {
        violations.compactMap { violation in
            switch violation {
            case .unknownDespiteErrors(let errorCount):
                return "The digest contains \(errorCount) ERROR/WARN line(s); category must not be unknown."
            case .categoryWithoutEvidence:
                return "The digest has no ERROR/WARN lines and no OOM signal; category must be unknown."
            case .suppressedCategory(let category):
                return "Category \(category.rawValue) is suppressed by a matched precheck rule; "
                    + "pick a different category."
            case .fabricatedEvidence(let term):
                return "The term \"\(term)\" does not appear in the digest; do not mention it."
            case .wrongCLIVocabulary:
                return nil
            }
        }
    }

    // MARK: - Private

    private func digestEvidenceLines(_ digest: LogDigest) -> [String] {
        digest.lastLines + digest.bootLines + digest.facts
    }

    private static func signalCount(in digest: LogDigest) -> Int {
        (digest.counts["ERROR"] ?? 0) + (digest.counts["WARN"] ?? 0)
    }

    private static func hasOOMSignal(in digest: LogDigest) -> Bool {
        let patternText = digest.topPatterns
            .flatMap { [$0.template, $0.sampleRaw] }
            .joined(separator: " ")
            .lowercased()
        return oomSignals.contains { patternText.contains($0) }
    }

    private static func repairDockerAction(_ action: String) -> String? {
        let trimmed = action.trimmingCharacters(in: .whitespacesAndNewlines)
        let lower = trimmed.lowercased()

        if lower.contains("docker-compose") || lower.contains("docker compose") {
            return nil
        }

        let replacements: [(String, String)] = [
            ("docker logs", "container logs"),
            ("docker inspect", "container inspect"),
            ("docker stop", "container stop"),
            ("docker start", "container start"),
            ("docker restart", "container restart"),
            ("docker rm", "container rm"),
            ("docker ps", "container list")
        ]

        for (from, to) in replacements where lower.contains(from) {
            return trimmed.replacingOccurrences(of: from, with: to, options: .caseInsensitive)
        }

        if lower.contains("docker") {
            return nil
        }

        return trimmed
    }

    private static func degradedCategory(
        modelCategory: FailureCategory,
        digest: LogDigest,
        violations: [DiagnosisViolation]
    ) -> FailureCategory {
        if violations.contains(where: {
            if case .categoryWithoutEvidence = $0 { return true }
            return false
        }) {
            return .unknown
        }

        if violations.contains(where: {
            if case .unknownDespiteErrors = $0 { return true }
            return false
        }) {
            if modelCategory != .unknown {
                return modelCategory
            }
            return inferCategory(from: digest)
        }

        return modelCategory == .unknown ? inferCategory(from: digest) : modelCategory
    }

    static func inferCategory(from digest: LogDigest) -> FailureCategory {
        let blob = ([digest.lastError, digest.firstError].compactMap { $0 }
            + digest.topPatterns.flatMap { [$0.template, $0.sampleRaw] }
            + digest.lastLines)
            .joined(separator: " ")
            .lowercased()

        if blob.contains("econnrefused") || blob.contains("connection refused") {
            return .dependencyUnreachable
        }
        if blob.contains("no space left") || blob.contains("disk full") {
            return .configuration
        }
        if oomSignals.contains(where: { blob.contains($0) }) {
            return .outOfMemory
        }
        if blob.contains("exception") || blob.contains("stacktrace") || blob.contains("stack trace")
            || blob.contains("caused by") {
            return .applicationBug
        }
        return .unknown
    }

    static func factSummary(for digest: LogDigest) -> String {
        let errorCount = signalCount(in: digest)
        var parts: [String] = []
        parts.append("Logs show \(errorCount) ERROR/WARN line(s)")
        if case .known(let exitCode, _) = digest.exitStatus {
            parts.append("exit code \(exitCode)")
        }
        if let lastError = digest.lastError {
            parts.append("last error: \(lastError)")
        } else if let firstError = digest.firstError {
            parts.append("first error: \(firstError)")
        }
        parts.append("automated diagnosis was inconclusive — review the digest evidence.")
        return parts.joined(separator: "; ") + "."
    }
}
