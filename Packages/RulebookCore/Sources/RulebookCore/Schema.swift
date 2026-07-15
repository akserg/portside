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

    public init(
        id: String,
        criteria: MatchCriteria,
        emitsFact: String,
        suppressesCategories: [String] = [],
        conclusionCategory: String? = nil,
        conclusionSummary: String? = nil
    ) {
        self.id = id
        self.criteria = criteria
        self.emitsFact = emitsFact
        self.suppressesCategories = suppressesCategories
        self.conclusionCategory = conclusionCategory
        self.conclusionSummary = conclusionSummary
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

    public static let always = MatchCriteria()

    public init(
        imagePrefix: String? = nil,
        exitCodes: [Int]? = nil,
        sources: [String]? = nil,
        logPatterns: [String]? = nil
    ) {
        self.imagePrefix = imagePrefix
        self.exitCodes = exitCodes
        self.sources = sources
        self.logPatterns = logPatterns
    }
}

public struct MatchContext: Sendable {
    public let image: String
    public let exitCode: Int?
    public let source: String
  /// Log window lines used for pattern matching (final boot cycle when applicable).
    public let logLines: [String]

    public init(image: String, exitCode: Int?, source: String, logLines: [String]) {
        self.image = image
        self.exitCode = exitCode
        self.source = source
        self.logLines = logLines
    }
}

/// Deterministic diagnosis returned when a precheck with conclusion fields matches.
public struct PrecheckConclusion: Sendable, Equatable {
    public let ruleID: String
    public let category: String
    public let summary: String

    public init(ruleID: String, category: String, summary: String) {
        self.ruleID = ruleID
        self.category = category
        self.summary = summary
    }
}
