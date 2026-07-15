import Foundation
import RulebookCore

/// Digest assembly output including the single rule evaluation for downstream stages.
public struct DigestBuildResult: Sendable, Equatable {
    public let digest: LogDigest
    public let evaluation: RuleEvaluation
    public let rulebookVersion: String
    public let rulebookSource: RulebookPipeline.RulebookSource
    public let fallbackReason: RulebookPipeline.FallbackReason?
    public let skippedUnknownKinds: [String]

    public init(
        digest: LogDigest,
        evaluation: RuleEvaluation,
        rulebookVersion: String,
        rulebookSource: RulebookPipeline.RulebookSource,
        fallbackReason: RulebookPipeline.FallbackReason? = nil,
        skippedUnknownKinds: [String]
    ) {
        self.digest = digest
        self.evaluation = evaluation
        self.rulebookVersion = rulebookVersion
        self.rulebookSource = rulebookSource
        self.fallbackReason = fallbackReason
        self.skippedUnknownKinds = skippedUnknownKinds
    }
}
