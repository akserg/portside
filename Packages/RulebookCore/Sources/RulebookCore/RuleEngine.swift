import Foundation

public struct RuleEvaluation: Sendable, Equatable {
    public let facts: [String]
    public let suppressedCategories: Set<String>
    public let noisePatterns: [String]
    public let promptRules: [PromptRule]
    public let evidenceRequirements: [String: [ValidatorRule]]
    /// Rules that actually fired (had an effect), not merely criteria-matched.
    /// Precheck: criteria matched. Noise: criteria matched AND linePattern hit at least one log line.
    /// Prompt/validator kinds are collected into their fields but omitted here until those
    /// layers are wired (B3 ships Layers 1-2 only).
    public let matchedRuleIDs: [String]
    /// First matched precheck with conclusion fields - bypasses the model when present.
    public let precheckConclusion: PrecheckConclusion?

    public init(
        facts: [String],
        suppressedCategories: Set<String>,
        noisePatterns: [String],
        promptRules: [PromptRule],
        evidenceRequirements: [String: [ValidatorRule]],
        matchedRuleIDs: [String],
        precheckConclusion: PrecheckConclusion? = nil
    ) {
        self.facts = facts
        self.suppressedCategories = suppressedCategories
        self.noisePatterns = noisePatterns
        self.promptRules = promptRules
        self.evidenceRequirements = evidenceRequirements
        self.matchedRuleIDs = matchedRuleIDs
        self.precheckConclusion = precheckConclusion
    }

    public static let empty = RuleEvaluation(
        facts: [],
        suppressedCategories: [],
        noisePatterns: [],
        promptRules: [],
        evidenceRequirements: [:],
        matchedRuleIDs: []
    )
}

public enum RuleEngine {

    public static func evaluate(_ rulebook: Rulebook, context: MatchContext) -> RuleEvaluation {
        var facts: [String] = []
        var suppressed: Set<String> = []
        var noise: [String] = []
        var prompts: [PromptRule] = []
        var evidence: [String: [ValidatorRule]] = [:]
        var fired: [String] = []
        var precheckConclusion: PrecheckConclusion?

        for rule in rulebook.rules {
            guard matches(rule.criteria, context: context) else { continue }
            switch rule {
            case .precheck(let rule):
                facts.append(rule.emitsFact)
                suppressed.formUnion(rule.suppressesCategories)
                fired.append(rule.id)
                if precheckConclusion == nil,
                   let category = rule.conclusionCategory,
                   let summary = rule.conclusionSummary {
                    precheckConclusion = PrecheckConclusion(
                        ruleID: rule.id,
                        category: category,
                        summary: summary
                    )
                }
            case .noise(let rule):
                // Criteria alone are not enough - require a real line hit so `.always`
                // noise rules don't appear "matched" on unrelated digests.
                guard anyLineMatches(rule.linePattern, lines: context.logLines) else { continue }
                noise.append(rule.linePattern)
                fired.append(rule.id)
            case .prompt(let rule):
                // Prompt layer stays hardcoded in B3 - collect for future, do not claim fired.
                prompts.append(rule)
            case .validator(let rule):
                // Validator layer stays hardcoded in B3 - collect for future, do not claim fired.
                evidence[rule.category, default: []].append(rule)
            }
        }

        prompts.sort { ($0.priority, $0.id) < ($1.priority, $1.id) }

        return RuleEvaluation(
            facts: facts,
            suppressedCategories: suppressed,
            noisePatterns: noise,
            promptRules: prompts,
            evidenceRequirements: evidence,
            matchedRuleIDs: fired,
            precheckConclusion: precheckConclusion
        )
    }

    public static func selectPromptRules(_ rules: [PromptRule], tokenBudget: Int) -> [PromptRule] {
        var remaining = tokenBudget
        var selected: [PromptRule] = []
        for rule in rules {
            let cost = estimatedTokens(rule.text)
            if cost <= remaining {
                selected.append(rule)
                remaining -= cost
            }
        }
        return selected
    }

    public static func estimatedTokens(_ text: String) -> Int {
        max(1, text.utf8.count / 4)
    }

    // MARK: - Matching

    static func matches(_ criteria: MatchCriteria, context: MatchContext) -> Bool {
        if let prefix = criteria.imagePrefix, !context.image.hasPrefix(prefix) {
            return false
        }
        if let codes = criteria.exitCodes {
            guard let exit = context.exitCode, codes.contains(exit) else { return false }
        }
        if let sources = criteria.sources, !sources.contains(context.source) {
            return false
        }
        if let patterns = criteria.logPatterns {
            for pattern in patterns {
                guard anyLineMatches(pattern, lines: context.logLines) else { return false }
            }
        }
        return true
    }

    public static func anyLineMatches(_ pattern: String, lines: [String]) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return false
        }
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            if regex.firstMatch(in: line, range: range) != nil { return true }
        }
        return false
    }

    public static func lineMatchesNoise(_ line: String, patterns: [String]) -> Bool {
        patterns.contains { anyLineMatches($0, lines: [line]) }
    }
}
