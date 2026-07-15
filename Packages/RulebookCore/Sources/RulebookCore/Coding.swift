import Foundation

extension Rulebook: Codable {
    private enum CodingKeys: String, CodingKey {
        case schemaVersion, version, minAppVersion, rules
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        guard schemaVersion <= Rulebook.currentSchemaVersion else {
            throw RulebookError.unsupportedSchemaVersion(schemaVersion)
        }

        var rulesContainer = try container.nestedUnkeyedContainer(forKey: .rules)
        var rules: [Rule] = []
        var skipped: [String] = []
        while !rulesContainer.isAtEnd {
            let wire = try rulesContainer.decode(WireRule.self)
            if let rule = wire.rule {
                rules.append(rule)
            } else {
                skipped.append(wire.kind)
            }
        }

        self.init(
            schemaVersion: schemaVersion,
            version: try container.decode(String.self, forKey: .version),
            minAppVersion: try container.decode(String.self, forKey: .minAppVersion),
            rules: rules,
            skippedUnknownKinds: skipped
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(version, forKey: .version)
        try container.encode(minAppVersion, forKey: .minAppVersion)
        try container.encode(rules.map(WireRule.init), forKey: .rules)
    }
}

public enum RulebookError: Error, Equatable, Sendable {
    case unsupportedSchemaVersion(Int)
    case invalidSignature
    case unknownKeyId(String)
    case malformedDocument
}

private struct WireRule: Codable {
    let kind: String
    let rule: Rule?

    init(_ rule: Rule) {
        self.rule = rule
        self.kind = switch rule {
        case .precheck: "precheck"
        case .noise: "noise"
        case .prompt: "prompt"
        case .validator: "validator"
        }
    }

    private enum CodingKeys: String, CodingKey { case kind }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decode(String.self, forKey: .kind)
        self.rule = switch kind {
        case "precheck": .precheck(try PrecheckRule(from: decoder))
        case "noise": .noise(try NoiseRule(from: decoder))
        case "prompt": .prompt(try PromptRule(from: decoder))
        case "validator": .validator(try ValidatorRule(from: decoder))
        default: nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        switch rule {
        case .precheck(let rule): try rule.encode(to: encoder)
        case .noise(let rule): try rule.encode(to: encoder)
        case .prompt(let rule): try rule.encode(to: encoder)
        case .validator(let rule): try rule.encode(to: encoder)
        case nil: throw RulebookError.malformedDocument
        }
    }
}
