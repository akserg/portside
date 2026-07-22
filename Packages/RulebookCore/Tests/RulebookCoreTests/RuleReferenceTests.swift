import Foundation
import Testing
@testable import RulebookCore

@Test func ruleReferenceRoundTripsKnownKind() throws {
    let reference = RuleReference(
        type: .runtimeBehavior,
        title: "Runtime sends SIGTERM before SIGKILL",
        url: "https://example.invalid/runtime",
        runtimeVersions: ["1.0.0"]
    )

    let encoded = try JSONEncoder().encode(reference)
    let decoded = try JSONDecoder().decode(RuleReference.self, from: encoded)

    #expect(decoded == reference)
}

@Test func unknownRuleReferenceKindRoundTripsVerbatim() throws {
    let json = #"{"type":"security-advisory","title":"Future metadata"}"#

    let decoded = try JSONDecoder().decode(RuleReference.self, from: Data(json.utf8))
    #expect(decoded.type.rawValue == "security-advisory")

    let encoded = try JSONEncoder().encode(decoded)
    let roundTripped = try JSONDecoder().decode(RuleReference.self, from: encoded)
    #expect(roundTripped.type.rawValue == "security-advisory")
}

@Test func absentReferencesKeyDecodesToEmpty() throws {
    let json = """
    {
      "schemaVersion": 1,
      "version": "0.1.0",
      "minAppVersion": "0.1.0",
      "rules": [
        { "kind": "noise", "id": "legacy", "criteria": {}, "linePattern": "noise" }
      ]
    }
    """

    let rulebook = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    guard case .noise(let rule) = rulebook.rules.first else {
        Issue.record("Expected a noise rule")
        return
    }
    #expect(rule.references == [])
}

@Test func referencesRoundTripOnEveryRuleKind() throws {
    let reference = RuleReference(type: .observed, title: "Observed in testing")
    let rulebook = Rulebook(
        version: "0.1.0",
        minAppVersion: "0.1.0",
        rules: [
            .precheck(PrecheckRule(
                id: "p", criteria: .always, emitsFact: "fact", references: [reference])),
            .noise(NoiseRule(
                id: "n", criteria: .always, linePattern: "noise", references: [reference])),
            .prompt(PromptRule(
                id: "pr", criteria: .always, text: "prompt", references: [reference])),
            .validator(ValidatorRule(
                id: "v", criteria: .always, category: "crash",
                requiredEvidence: ["crash"], references: [reference])),
        ]
    )

    let encoded = try JSONEncoder().encode(rulebook)
    let decoded = try JSONDecoder().decode(Rulebook.self, from: encoded)
    #expect(decoded == rulebook)
}

@Test func unknownReferenceKindDecodesOnRule() throws {
    let json = """
    {
      "schemaVersion": 1,
      "version": "0.1.0",
      "minAppVersion": "0.1.0",
      "rules": [{
        "kind": "noise",
        "id": "n",
        "criteria": {},
        "linePattern": "noise",
        "references": [{"type": "security-advisory", "title": "Future source"}]
      }]
    }
    """

    let rulebook = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    guard case .noise(let rule) = rulebook.rules.first else {
        Issue.record("Expected a noise rule")
        return
    }
    #expect(rule.references.first?.type.rawValue == "security-advisory")
}

@Test(arguments: [
    #"{"type":"observed"}"#,
    #"{"title":"Missing type"}"#,
    #""not-an-array""#,
    #"null"#,
])
func malformedReferencesValueFails(referenceValue: String) {
    let json = """
    {
      "schemaVersion": 1,
      "version": "0.1.0",
      "minAppVersion": "0.1.0",
      "rules": [{
        "kind": "noise",
        "id": "n",
        "criteria": {},
        "linePattern": "noise",
        "references": [REFERENCE_VALUE]
      }]
    }
    """.replacingOccurrences(of: "[REFERENCE_VALUE]", with: referenceValue)

    #expect(throws: (any Error).self) {
        _ = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    }
}
