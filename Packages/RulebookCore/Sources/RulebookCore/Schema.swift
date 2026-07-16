import Foundation

// MARK: - Rulebook document

/// A versioned, signed collection of diagnosis rules.
public struct Rulebook: Sendable, Equatable {
    public static let currentSchemaVersion = 1

    public let schemaVersion: Int
    public let version: String
    public let minAppVersion: String
    public let rules: [Rule]
    public let skippedUnknownKinds: [String]

    public init(
        schemaVersion: Int = Rulebook.currentSchemaVersion,
        version: String,
        minAppVersion: String,
        rules: [Rule],
        skippedUnknownKinds: [String] = []
    ) {
        self.schemaVersion = schemaVersion
        self.version = version
        self.minAppVersion = minAppVersion
        self.rules = rules
        self.skippedUnknownKinds = skippedUnknownKinds
    }
}

// MARK: - Rules

public enum Rule: Sendable, Equatable {
    case precheck(PrecheckRule)
    case noise(NoiseRule)
    case prompt(PromptRule)
    case validator(ValidatorRule)

    public var id: String {
        switch self {
        case .precheck(let rule): rule.id
        case .noise(let rule): rule.id
        case .prompt(let rule): rule.id
        case .validator(let rule): rule.id
        }
    }

    public var criteria: MatchCriteria {
        switch self {
        case .precheck(let rule): rule.criteria
        case .noise(let rule): rule.criteria
        case .prompt(let rule): rule.criteria
        case .validator(let rule): rule.criteria
        }
    }
}

/// Deterministic pre-model check: emits facts, may suppress categories, and may
/// short-circuit the model with a fixed conclusion when `conclusionCategory` is set.
public struct PrecheckRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let emitsFact: String
    public let suppressesCategories: [String]
    /// When set with `conclusionSummary`, diagnosis bypasses the model (deterministic).
    public let conclusionCategory: String?
    public let conclusionSummary: String?
    /// Confidence wire value (`ContainerDiagnosis.Confidence` raw) for the conclusion.
    /// Absent → consumer default (preserves the pre-B8 `.high` short-circuit behavior).
    public let conclusionConfidence: String?
    /// Suggested actions for the conclusion. Absent → consumer default. The `{container}`
    /// token is substituted with the container id by the consumer.
    public let conclusionActions: [String]?

    public init(
        id: String,
        criteria: MatchCriteria,
        emitsFact: String,
        suppressesCategories: [String] = [],
        conclusionCategory: String? = nil,
        conclusionSummary: String? = nil,
        conclusionConfidence: String? = nil,
        conclusionActions: [String]? = nil
    ) {
        self.id = id
        self.criteria = criteria
        self.emitsFact = emitsFact
        self.suppressesCategories = suppressesCategories
        self.conclusionCategory = conclusionCategory
        self.conclusionSummary = conclusionSummary
        self.conclusionConfidence = conclusionConfidence
        self.conclusionActions = conclusionActions
    }
}

/// Marks log lines as known noise. WharfsideAnalysis demotes matching **boot-source**
/// lines only (stdio lines are never demoted by noise rules).
public struct NoiseRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let linePattern: String

    public init(id: String, criteria: MatchCriteria, linePattern: String) {
        self.id = id
        self.criteria = criteria
        self.linePattern = linePattern
    }
}

public struct PromptRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let text: String
    public let priority: Int

    public init(id: String, criteria: MatchCriteria, text: String, priority: Int = 100) {
        self.id = id
        self.criteria = criteria
        self.text = text
        self.priority = priority
    }
}

public struct ValidatorRule: Sendable, Equatable, Codable {
    public let id: String
    public let criteria: MatchCriteria
    public let category: String
    public let requiredEvidence: [String]

    public init(id: String, criteria: MatchCriteria, category: String, requiredEvidence: [String]) {
        self.id = id
        self.criteria = criteria
        self.category = category
        self.requiredEvidence = requiredEvidence
    }
}

// MARK: - Matching

public struct MatchCriteria: Sendable, Equatable, Codable {
    public let imagePrefix: String?
    public let exitCodes: [Int]?
    public let sources: [String]?
    public let logPatterns: [String]?
    /// Matches only when `MatchContext.errorLineCount <= maxErrorCount`
    /// (e.g. `0` = "no error-level content in the window").
    public let maxErrorCount: Int?
    /// Matches only when NONE of these patterns match any log line (negative predicate;
    /// e.g. exclude the stop signature so a fallback precheck does not double-fire).
    public let excludesLogPatterns: [String]?
    /// Matches unless `MatchContext.exitCode` is present AND in this list
    /// (e.g. `[0]` excludes a clean exit-0). A nil (unresolved) exit code is treated as
    /// "not excluded" so evidence-free digests are still caught; the consumer drops the
    /// exit parenthetical from the summary when the code is unresolved.
    public let excludesExitCodes: [Int]?

    public static let always = MatchCriteria()

    public init(
        imagePrefix: String? = nil,
        exitCodes: [Int]? = nil,
        sources: [String]? = nil,
        logPatterns: [String]? = nil,
        maxErrorCount: Int? = nil,
        excludesLogPatterns: [String]? = nil,
        excludesExitCodes: [Int]? = nil
    ) {
        self.imagePrefix = imagePrefix
        self.exitCodes = exitCodes
        self.sources = sources
        self.logPatterns = logPatterns
        self.maxErrorCount = maxErrorCount
        self.excludesLogPatterns = excludesLogPatterns
        self.excludesExitCodes = excludesExitCodes
    }
}

public struct MatchContext: Sendable {
    public let image: String
    public let exitCode: Int?
    public let source: String
  /// Log window lines used for pattern matching (final boot cycle when applicable).
    public let logLines: [String]
    /// Count of ERROR-level entries in the same window as `logLines`. App-derived so
    /// `MatchCriteria.maxErrorCount` can key on "no error content" structurally.
    public let errorLineCount: Int

    public init(
        image: String,
        exitCode: Int?,
        source: String,
        logLines: [String],
        errorLineCount: Int = 0
    ) {
        self.image = image
        self.exitCode = exitCode
        self.source = source
        self.logLines = logLines
        self.errorLineCount = errorLineCount
    }
}

/// Deterministic diagnosis returned when a precheck with conclusion fields matches.
public struct PrecheckConclusion: Sendable, Equatable {
    public let ruleID: String
    public let category: String
    public let summary: String
    /// Confidence wire value from the rule; nil → consumer default (`.high`).
    public let confidence: String?
    /// Suggested actions from the rule (with `{container}` tokens); nil → consumer default.
    public let suggestedActions: [String]?

    public init(
        ruleID: String,
        category: String,
        summary: String,
        confidence: String? = nil,
        suggestedActions: [String]? = nil
    ) {
        self.ruleID = ruleID
        self.category = category
        self.summary = summary
        self.confidence = confidence
        self.suggestedActions = suggestedActions
    }
}
