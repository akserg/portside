import Crypto
import Foundation
import Testing
@testable import RulebookCore

private let report2Context = MatchContext(
    image: "docker.io/library/alpine:latest",
    exitCode: 137,
    source: "bootLogOnly",
    logLines: [
        "2026-07-09T05:54:30.774Z warning vminitd: current_bytes: 83759104 vminitd memory threshold exceeded",
        "2026-07-09T05:54:30.776Z info vminitd: id: hello, pid: 109 started managed process",
        "2026-07-09T05:54:47.329Z info vminitd: id: hello sending signal 15 to process 109",
        "2026-07-09T05:54:57.792Z info vminitd: id: hello sending signal 9 to process 109",
        "2026-07-09T05:54:57.794Z info vminitd: id: hello, status: 137 managed process exit",
    ]
)

@Test func report2ScenarioIsClassifiedAsOrderlyStopNotOOM() throws {
    let evaluation = RuleEngine.evaluate(SeedRulebook.make(), context: report2Context)

    #expect(evaluation.facts.count == 1)
    #expect(evaluation.facts[0].contains("orderly stop"))
    #expect(evaluation.suppressedCategories.contains("outOfMemory"))
    #expect(evaluation.noisePatterns.contains(#"vminitd memory threshold exceeded"#))
    #expect(evaluation.matchedRuleIDs == [
        "precheck.stop-escalation",
        "noise.vminitd-memory-threshold",
    ])

    let conclusion = try #require(evaluation.precheckConclusion)
    #expect(conclusion.ruleID == "precheck.stop-escalation")
    #expect(conclusion.category == "stopped")
    #expect(conclusion.summary.contains("SIGTERM/SIGKILL"))
}

@Test func noiseDoesNotFireWithoutMatchingLine() {
    let context = MatchContext(
        image: "docker.io/library/alpine:latest",
        exitCode: 1,
        source: "stdio",
        logLines: [
            "ERROR: No space left on device",
            "head: invalid number '10M'",
        ]
    )
    let evaluation = RuleEngine.evaluate(SeedRulebook.make(), context: context)
    #expect(evaluation.noisePatterns.isEmpty)
    #expect(!evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(evaluation.matchedRuleIDs.isEmpty)
}

@Test func precheckDoesNotFireOnGenuineOOM() {
    let context = MatchContext(
        image: "docker.io/library/postgres:16",
        exitCode: 137,
        source: "stdio",
        logLines: [
            "kernel: Out of memory: Killed process 109 (postgres)",
            "kernel: oom_reaper: reaped process 109",
        ]
    )
    let evaluation = RuleEngine.evaluate(SeedRulebook.make(), context: context)
    #expect(evaluation.facts.isEmpty)
    #expect(evaluation.precheckConclusion == nil)
    #expect(!evaluation.suppressedCategories.contains("outOfMemory"))
    #expect(!evaluation.matchedRuleIDs.contains("precheck.stop-escalation"))
}

@Test func precheckDoesNotRequireWharfsideStopRecord() {
    let evaluation = RuleEngine.evaluate(SeedRulebook.make(), context: report2Context)
    #expect(evaluation.precheckConclusion != nil)
}

@Test func seedRulebookIsLayersOneAndTwoOnly() {
    let kinds = SeedRulebook.make().rules.map { rule -> String in
        switch rule {
        case .precheck: "precheck"
        case .noise: "noise"
        case .prompt: "prompt"
        case .validator: "validator"
        }
    }
    #expect(Set(kinds) == Set(["precheck", "noise"]))
}

@Test func promptAndValidatorCriteriaMatchDoNotCountAsFired() {
    let book = Rulebook(
        version: "test",
        minAppVersion: "0.1.1",
        rules: [
            .prompt(PromptRule(
                id: "prompt.exit-137-stop-hint",
                criteria: MatchCriteria(exitCodes: [137]),
                text: "hint",
                priority: 10
            )),
            .validator(ValidatorRule(
                id: "validator.oom-needs-kernel-evidence",
                criteria: .always,
                category: "outOfMemory",
                requiredEvidence: [#"oom-kill"#]
            )),
        ]
    )
    let evaluation = RuleEngine.evaluate(book, context: report2Context)
    #expect(evaluation.promptRules.map(\.id) == ["prompt.exit-137-stop-hint"])
    #expect(evaluation.evidenceRequirements["outOfMemory"]?.count == 1)
    #expect(evaluation.matchedRuleIDs.isEmpty)
}

@Test func rulebookRoundTripsThroughJSON() throws {
    let original = SeedRulebook.make()
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(Rulebook.self, from: data)
    #expect(decoded == original)
}

@Test func bundledJSONMatchesSeedRulebook() throws {
    let decoded = try RulebookLoader.loadBundled(SeedRulebook.bundledJSON)
    #expect(decoded == SeedRulebook.make())
}

@Test func unknownRuleKindsAreSkippedNotFatal() throws {
    let json = """
    {
      "schemaVersion": 1,
      "version": "0.2.0",
      "minAppVersion": "1.0.0",
      "rules": [
        { "kind": "hologram", "payload": { "future": true } },
        { "kind": "noise", "id": "n1", "criteria": {},
          "linePattern": "Bridge firewalling registered" }
      ]
    }
    """
    let book = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    #expect(book.rules.count == 1)
    #expect(book.skippedUnknownKinds == ["hologram"])
}

@Test func newerSchemaVersionIsRejected() {
    let json = """
    { "schemaVersion": 99, "version": "9.0.0", "minAppVersion": "1.0.0", "rules": [] }
    """
    #expect(throws: RulebookError.unsupportedSchemaVersion(99)) {
        _ = try JSONDecoder().decode(Rulebook.self, from: Data(json.utf8))
    }
}

@Test func exitCodeCriterionFailsWhenExitCodeIsNil() {
    let criteria = MatchCriteria(exitCodes: [137])
    let noExit = MatchContext(
        image: report2Context.image,
        exitCode: nil,
        source: "bootLogOnly",
        logLines: report2Context.logLines
    )
    #expect(!RuleEngine.matches(criteria, context: noExit))
}

@Test func malformedRegexFailsClosed() {
    #expect(!RuleEngine.anyLineMatches("([unclosed", lines: ["([unclosed"]))
}

// MARK: - B8 wire-vocabulary predicates

private func context(
    exitCode: Int?,
    logLines: [String],
    errorLineCount: Int = 0
) -> MatchContext {
    MatchContext(
        image: "docker.io/library/alpine:latest",
        exitCode: exitCode,
        source: "bootLogOnly",
        logLines: logLines,
        errorLineCount: errorLineCount
    )
}

@Test func maxErrorCountBlocksWhenErrorsExceedThreshold() {
    let criteria = MatchCriteria(maxErrorCount: 0)
    #expect(!RuleEngine.matches(criteria, context: context(exitCode: 1, logLines: ["boom"], errorLineCount: 1)))
    #expect(RuleEngine.matches(criteria, context: context(exitCode: 1, logLines: ["quiet"], errorLineCount: 0)))
}

@Test func excludesLogPatternsBlocksWhenAnyPatternMatches() {
    let criteria = MatchCriteria(excludesLogPatterns: ["sending signal 15 to process"])
    let withSignal = context(exitCode: 137, logLines: ["id: hello sending signal 15 to process 109"])
    let withoutSignal = context(exitCode: 1, logLines: ["id: crush, status: 1 managed process exit"])
    #expect(!RuleEngine.matches(criteria, context: withSignal))
    #expect(RuleEngine.matches(criteria, context: withoutSignal))
}

@Test func excludesExitCodesBlocksListedCodeButAllowsOthersAndNil() {
    let criteria = MatchCriteria(excludesExitCodes: [0])
    #expect(!RuleEngine.matches(criteria, context: context(exitCode: 0, logLines: ["x"])))
    #expect(RuleEngine.matches(criteria, context: context(exitCode: 1, logLines: ["x"])))
    // A nil (unresolved) exit is treated as "not excluded" so evidence-free digests still match.
    #expect(RuleEngine.matches(criteria, context: context(exitCode: nil, logLines: ["x"])))
}

@Test func precheckConclusionCarriesRuleConfidenceAndActions() {
    let rule = Rule.precheck(PrecheckRule(
        id: "precheck.no-evidence",
        criteria: MatchCriteria(sources: ["bootLogOnly"], maxErrorCount: 0, excludesExitCodes: [0]),
        emitsFact: "EVIDENCE: none",
        conclusionCategory: "unknown",
        conclusionSummary: "The container exited{exit_status} without writing any application output.",
        conclusionConfidence: "low",
        conclusionActions: ["Run `container logs {container}` to confirm no output was produced"]
    ))
    let book = Rulebook(version: "test", minAppVersion: "0.1.1", rules: [rule])
    let evaluation = RuleEngine.evaluate(book, context: context(exitCode: 1, logLines: ["quiet"]))
    let conclusion = evaluation.precheckConclusion
    #expect(conclusion?.confidence == "low")
    #expect(conclusion?.suggestedActions == ["Run `container logs {container}` to confirm no output was produced"])
}

@Test func signatureVerificationAcceptsValidRejectsTampered() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try JSONEncoder().encode(SeedRulebook.make())
    let signature = try key.signature(for: document)

    let loaded = try RulebookLoader.loadVerified(
        document: document,
        signature: signature,
        publicKey: key.publicKey
    )
    #expect(loaded.version == SeedRulebook.version)

    var tampered = document
    tampered.append(contentsOf: [0x20])
    #expect(throws: RulebookError.invalidSignature) {
        _ = try RulebookLoader.loadVerified(
            document: tampered,
            signature: signature,
            publicKey: key.publicKey
        )
    }
}

@Test func envelopeLoadVerifiedRejectsUnknownKeyIdAndTamper() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try Data(
        contentsOf: Bundle.module.url(forResource: "Rulebook", withExtension: "json")!
    )
    let envelope = try RulebookSignatureEnvelope.sign(
        document: document,
        privateKey: key,
        keyId: "test-key"
    )
    let trusted = ["test-key": key.publicKey]

    let loaded = try RulebookLoader.loadVerified(
        document: document,
        envelope: envelope,
        trustedKeys: trusted
    )
    #expect(loaded.version == SeedRulebook.version)

    #expect(throws: RulebookError.unknownKeyId("other-key")) {
        _ = try RulebookLoader.loadVerified(
            document: document,
            envelope: RulebookSignatureEnvelope(keyId: "other-key", signature: envelope.signature),
            trustedKeys: trusted
        )
    }

    var tampered = document
    tampered[tampered.startIndex] ^= 0x01
    #expect(throws: RulebookError.invalidSignature) {
        _ = try RulebookLoader.loadVerified(
            document: tampered,
            envelope: envelope,
            trustedKeys: trusted
        )
    }
}

@Test func pinnedTrustVerifiesBundledRulebookResource() throws {
    let document = try Data(
        contentsOf: Bundle.module.url(forResource: "Rulebook", withExtension: "json")!
    )
    let envelopeData = try Data(
        contentsOf: Bundle.module.url(forResource: "Rulebook.json", withExtension: "sig")!
    )
    let envelope = try JSONDecoder().decode(RulebookSignatureEnvelope.self, from: envelopeData)
    let loaded = try RulebookLoader.loadVerified(document: document, envelope: envelope)
    #expect(loaded == SeedRulebook.make())
    #expect(envelope.keyId == RulebookTrust.currentKeyID)
}

@Test func nonJSONBytesFailToDecode() {
    #expect(throws: (any Error).self) {
        _ = try RulebookLoader.loadBundled(Data("not json".utf8))
    }
}

@Test func truncatedJSONFailsToDecode() throws {
    let data = try SeedRulebook.bundledJSON
    let truncated = data.prefix(data.count / 2)
    #expect(throws: (any Error).self) {
        _ = try RulebookLoader.loadBundled(Data(truncated))
    }
}

@Test func corruptJSONBracketFailsToDecode() throws {
    var data = try SeedRulebook.bundledJSON
    data[data.startIndex] = data[data.startIndex] == UInt8(ascii: "{") ? UInt8(ascii: "[") : UInt8(ascii: "{")
    #expect(throws: (any Error).self) {
        _ = try RulebookLoader.loadBundled(data)
    }
}
