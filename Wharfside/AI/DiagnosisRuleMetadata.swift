// AI/DiagnosisRuleMetadata.swift
// Rulebook transparency for diagnosis reports (RULEBOOK_INTEGRATION.md §8).

import Foundation
import RulebookCore
import WharfsideAnalysis

struct DiagnosisRuleMetadata: Sendable, Equatable {
    let rulebookVersion: String
    let rulebookSource: RulebookPipeline.RulebookSource
    let fallbackReason: RulebookPipeline.FallbackReason?
    let matchedRuleIDs: [String]
    let skippedUnknownKinds: [String]
    let precheckRuleID: String?

    nonisolated static let empty = DiagnosisRuleMetadata(
        rulebookVersion: SeedRulebook.version,
        rulebookSource: .fallback,
        fallbackReason: nil,
        matchedRuleIDs: [],
        skippedUnknownKinds: [],
        precheckRuleID: nil
    )

    nonisolated init(
        rulebookVersion: String,
        rulebookSource: RulebookPipeline.RulebookSource,
        fallbackReason: RulebookPipeline.FallbackReason? = nil,
        matchedRuleIDs: [String],
        skippedUnknownKinds: [String],
        precheckRuleID: String?
    ) {
        self.rulebookVersion = rulebookVersion
        self.rulebookSource = rulebookSource
        self.fallbackReason = fallbackReason
        self.matchedRuleIDs = matchedRuleIDs
        self.skippedUnknownKinds = skippedUnknownKinds
        self.precheckRuleID = precheckRuleID
    }

    nonisolated init(buildResult: DigestBuildResult) {
        self.rulebookVersion = buildResult.rulebookVersion
        self.rulebookSource = buildResult.rulebookSource
        self.fallbackReason = buildResult.fallbackReason
        self.matchedRuleIDs = buildResult.evaluation.matchedRuleIDs
        self.skippedUnknownKinds = buildResult.skippedUnknownKinds
        self.precheckRuleID = buildResult.evaluation.precheckConclusion?.ruleID
    }

    nonisolated var footerLine: String {
        Self.formatFooterLine(
            rulebookVersion: rulebookVersion,
            rulebookSource: rulebookSource,
            fallbackReason: fallbackReason,
            matchedRuleIDs: matchedRuleIDs,
            skippedUnknownKinds: skippedUnknownKinds
        )
    }

    nonisolated static func formatFooterLine(
        rulebookVersion: String,
        rulebookSource: RulebookPipeline.RulebookSource,
        fallbackReason: RulebookPipeline.FallbackReason? = nil,
        matchedRuleIDs: [String],
        skippedUnknownKinds: [String]
    ) -> String {
        let identity: String
        switch rulebookSource {
        case .bundled:
            identity = "\(rulebookVersion) (bundled)"
        case .fallback:
            let reasonLabel: String
            if let fallbackReason {
                switch fallbackReason {
                case .signatureInvalid: reasonLabel = "signature"
                case .malformed: reasonLabel = "malformed"
                case .missing: reasonLabel = "missing"
                }
                identity = "seed (bundled rulebook rejected: \(reasonLabel))"
            } else {
                identity = "seed (fallback)"
            }
        }
        let matched = matchedRuleIDs.isEmpty ? "none" : matchedRuleIDs.joined(separator: ", ")
        let skipped = skippedUnknownKinds.isEmpty ? "none" : skippedUnknownKinds.joined(separator: ", ")
        return "Rulebook: \(identity) · Rules fired: \(matched) · "
            + "Skipped unknown rule kinds: \(skipped)"
    }
}

enum PrecheckDiagnosisBuilder {
    static func diagnosis(
        from conclusion: PrecheckConclusion,
        containerName: String
    ) -> ContainerDiagnosis? {
        guard let category = failureCategory(for: conclusion.category) else { return nil }
        return ContainerDiagnosis(
            summary: conclusion.summary,
            category: category,
            suggestedActions: orderlyStopActions(containerName: containerName),
            confidence: .high
        )
    }

    private static func orderlyStopActions(containerName: String) -> [String] {
        [
            "Review boot log with `container logs \(containerName) --boot` if you need to confirm the stop path"
        ]
    }

    private static func failureCategory(for wireValue: String) -> FailureCategory? {
        FailureCategory(rawValue: wireValue)
    }
}
