import Crypto
import Foundation
import RulebookCore
import Testing
@testable import WharfsideAnalysis

@Test func matchContextScopesBootLogToFinalCycle() throws {
    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )

    let matchContext = MatchContextBuilder.make(entries: entries, context: context)
    #expect(matchContext.exitCode == 137)
    #expect(matchContext.source == "bootLogOnly")
    #expect(matchContext.logLines.contains { $0.contains("sending signal 15 to process") })
    #expect(matchContext.logLines.contains { $0.contains("status: 137 managed process exit") })
    #expect(matchContext.logLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
    #expect(!matchContext.logLines.contains { $0.contains("sending signal 15") && $0.contains("2026-07-06") })
}

@Test func matchContextCountsErrorLevelLinesInWindow() throws {
    // diag-crash: boot-only, exit 1, only vminitd info/warn lines → zero ERROR level.
    let clean = try LabeledFixtureLoader.loadLog(named: "exit_no_output_misdiagnosed_or_timeout.log")
    let cleanContext = MatchContextBuilder.make(
        entries: clean,
        context: ContainerContext(
            containerName: "diag-crush",
            image: "docker.io/library/alpine:latest",
            exitStatus: .known(1, source: .bootLog),
            restartCount: 0
        )
    )
    #expect(cleanContext.source == "bootLogOnly")
    #expect(cleanContext.exitCode == 1)
    #expect(cleanContext.errorLineCount == 0)

    // boot_only_crash: boot-only WITH ERROR/FATAL content → nonzero error count.
    let errored = try LabeledFixtureLoader.loadLog(named: "boot_only_crash.log")
    let errContext = MatchContextBuilder.make(
        entries: errored,
        context: ContainerContext(
            containerName: "crash",
            image: "alpine:latest",
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0
        )
    )
    #expect(errContext.source == "bootLogOnly")
    #expect(errContext.errorLineCount >= 1)
}

@Test func report2DigestDemotesVminitdNoiseAndEmitsPrecheckFact() throws {
    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let window = DigestWindow(description: "logs before container exit")
    let result = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: window
    )
    let rendered = PromptRenderer().render(result.digest)

    #expect(result.evaluation.precheckConclusion?.ruleID == "precheck.stop-escalation")
    #expect(result.evaluation.precheckConclusion?.category == "stopped")
    #expect(result.evaluation.matchedRuleIDs.contains("precheck.stop-escalation"))
    #expect(result.evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(result.digest.facts.contains { $0.contains("orderly stop") })
    #expect(rendered.contains("FACTS:"))
    #expect(!result.digest.lastLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
    #expect(!result.digest.topPatterns.contains {
        $0.template.localizedCaseInsensitiveContains("memory threshold")
    })
    #expect(rendered.contains("sending signal 15 to process"))
    #expect(rendered.contains("sending signal 9 to process"))
    #expect(rendered.contains("status: 137 managed process exit"))
    #expect(rendered.contains("EXIT_CODE: 137 (from boot log)"))
    // Digest16: COUNTS collapsed to final cycle (INFO=27, not multi-boot 230).
    #expect(result.digest.counts["INFO", default: 0] == 27)
    #expect(rendered.contains("COUNTS: INFO=27"))
    // Final-cycle scoping: no multi-boot [10x] kernel spam from earlier cycles.
    #expect(!result.digest.topPatterns.contains { $0.count >= 10 })
    #expect(!rendered.contains("[10x]"))
}

@Test func matchContextAndDigestShareFinalCycleWindow() throws {
    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let matchContext = MatchContextBuilder.make(entries: entries, context: context)
    #expect(matchContext.logLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
    #expect(matchContext.logLines.contains { $0.contains("started managed process") })
    #expect(matchContext.logLines.contains { $0.contains("sending signal 15") })

    let evaluation = RulebookPipeline.load(rulebookData: nil).evaluate(entries: entries, context: context)
    #expect(evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
}

@Test func bootNoiseContaminationDemotesBootOnlyVminitdLines() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "boot_noise_contamination.log")
    let context = ContainerContext(
        containerName: "crashy",
        image: "crashy:latest",
        exitStatus: .known(1, source: .runtime),
        restartCount: 0
    )
    let result = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    )
    let digest = result.digest
    let rendered = PromptRenderer().render(digest)

    #expect(digest.counts["ERROR", default: 0] == 1)
    #expect(digest.firstError?.contains("No space left on device") == true)
    #expect(!digest.bootLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
    #expect(!digest.topPatterns.contains { $0.template.localizedCaseInsensitiveContains("vminitd") })
    #expect(rendered.contains("BOOT_LOG"))
}

@Test func hostileStdioForgedSignalsDoNotTriggerPrecheck() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_hostile_stdio.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let result = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    )

    #expect(result.evaluation.precheckConclusion == nil)
    #expect(result.digest.lastLines.contains { $0.contains("sending signal 15") })
    #expect(!result.digest.bootLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
}

@Test func corruptJSONBracketFallsBackToSeedRules() throws {
    var data = try SeedRulebook.bundledJSON
    data[data.startIndex] = data[data.startIndex] == UInt8(ascii: "{") ? UInt8(ascii: "[") : UInt8(ascii: "{")
    // Unsigned bytes are refused before decode (signature gate).
    let pipeline = RulebookPipeline.load(rulebookData: data)
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)
    #expect(pipeline.rulebook == SeedRulebook.make())
}

@Test func nonJSONBytesFallBackToSeedRules() {
    let pipeline = RulebookPipeline.load(rulebookData: Data("not json".utf8))
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)
    #expect(pipeline.rulebook == SeedRulebook.make())
}

@Test func truncatedJSONFallsBackToSeedRules() throws {
    let data = try SeedRulebook.bundledJSON
    let truncated = Data(data.prefix(data.count / 2))
    let pipeline = RulebookPipeline.load(rulebookData: truncated)
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)
    #expect(pipeline.rulebook == SeedRulebook.make())
}

/// Unsigned / rejected rulebook → fallback → report2 still evaluates seed precheck + noise (I4/I6).
@Test func malformedRulebookFallbackStillDiagnosesReport2ViaSeed() throws {
    let pipeline = RulebookPipeline.load(rulebookData: Data("not json".utf8))
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)

    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let result = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit"),
        rulebookPipeline: pipeline
    )
    #expect(result.rulebookSource == .fallback)
    #expect(result.fallbackReason == .signatureInvalid)
    #expect(result.evaluation.precheckConclusion?.ruleID == "precheck.stop-escalation")
    #expect(result.evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(!result.digest.lastLines.contains { $0.localizedCaseInsensitiveContains("memory threshold exceeded") })
}

@Test func verifiedBundledRulebookLoadsHappyPath() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try JSONEncoder().encode(SeedRulebook.make())
    let envelope = try RulebookSignatureEnvelope.sign(
        document: document,
        privateKey: key,
        keyId: "pipeline-test"
    )
    let pipeline = RulebookPipeline.load(
        rulebookData: document,
        signatureData: try JSONEncoder().encode(envelope),
        trustedKeys: ["pipeline-test": key.publicKey]
    )
    #expect(pipeline.source == .bundled)
    #expect(pipeline.fallbackReason == nil)
    #expect(pipeline.rulebook == SeedRulebook.make())
}

@Test func tamperedDocumentFallsBackWithSignatureInvalidReason() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try JSONEncoder().encode(SeedRulebook.make())
    let envelope = try RulebookSignatureEnvelope.sign(
        document: document,
        privateKey: key,
        keyId: "pipeline-test"
    )
    var tampered = document
    tampered[tampered.startIndex] ^= 0x01
    let pipeline = RulebookPipeline.load(
        rulebookData: tampered,
        signatureData: try JSONEncoder().encode(envelope),
        trustedKeys: ["pipeline-test": key.publicKey]
    )
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)
    #expect(pipeline.rulebook == SeedRulebook.make())
}

@Test func wrongKeyIdFallsBackWithSignatureInvalidReason() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = try JSONEncoder().encode(SeedRulebook.make())
    let envelope = try RulebookSignatureEnvelope.sign(
        document: document,
        privateKey: key,
        keyId: "pipeline-test"
    )
    let wrong = RulebookSignatureEnvelope(keyId: "other-key", signature: envelope.signature)
    let pipeline = RulebookPipeline.load(
        rulebookData: document,
        signatureData: try JSONEncoder().encode(wrong),
        trustedKeys: ["pipeline-test": key.publicKey]
    )
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .signatureInvalid)
}

@Test func signedMalformedDocumentFallsBackWithMalformedReason() throws {
    let key = Curve25519.Signing.PrivateKey()
    let document = Data("not json".utf8)
    let envelope = try RulebookSignatureEnvelope.sign(
        document: document,
        privateKey: key,
        keyId: "pipeline-test"
    )
    let pipeline = RulebookPipeline.load(
        rulebookData: document,
        signatureData: try JSONEncoder().encode(envelope),
        trustedKeys: ["pipeline-test": key.publicKey]
    )
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .malformed)
}

@Test func missingRulebookFallsBackWithMissingReason() {
    let pipeline = RulebookPipeline.load(rulebookData: nil)
    #expect(pipeline.source == .fallback)
    #expect(pipeline.fallbackReason == .missing)
}

@Test func fallbackReasonsProduceIdenticalReport2Diagnosis() throws {
    let key = Curve25519.Signing.PrivateKey()
    let goodDocument = try JSONEncoder().encode(SeedRulebook.make())
    let goodEnvelope = try RulebookSignatureEnvelope.sign(
        document: goodDocument,
        privateKey: key,
        keyId: "pipeline-test"
    )
    var tampered = goodDocument
    tampered[tampered.startIndex] ^= 0x01
    let signedJunk = Data("not json".utf8)
    let junkEnvelope = try RulebookSignatureEnvelope.sign(
        document: signedJunk,
        privateKey: key,
        keyId: "pipeline-test"
    )
    let trusted = ["pipeline-test": key.publicKey]

    let pipelines = [
        RulebookPipeline.load(rulebookData: nil),
        RulebookPipeline.load(
            rulebookData: tampered,
            signatureData: try JSONEncoder().encode(goodEnvelope),
            trustedKeys: trusted
        ),
        RulebookPipeline.load(
            rulebookData: signedJunk,
            signatureData: try JSONEncoder().encode(junkEnvelope),
            trustedKeys: trusted
        )
    ]
    #expect(pipelines.map(\.fallbackReason) == [.missing, .signatureInvalid, .malformed])

    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let digests = pipelines.map { pipeline in
        PromptRenderer().render(
            LogDigestBuilder().buildWithRules(
                entries: entries,
                context: context,
                window: DigestWindow(description: "logs before container exit"),
                rulebookPipeline: pipeline
            ).digest
        )
    }
    #expect(digests[0] == digests[1])
    #expect(digests[1] == digests[2])
}

@Test func crashyDigestDoesNotClaimNoiseFiredWithoutThresholdLine() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "boot_noise_contamination.log")
    // Strip the threshold-exceeded boot lines so only config-style noise remains —
    // the stdio disk-full case must not list noise.vminitd-memory-threshold as fired.
    let withoutThreshold = entries.filter {
        !$0.raw.localizedCaseInsensitiveContains("memory threshold exceeded")
    }
    let context = ContainerContext(
        containerName: "crashy",
        image: "crashy:latest",
        exitStatus: .known(1, source: .runtime),
        restartCount: 0
    )
    let result = LogDigestBuilder().buildWithRules(
        entries: withoutThreshold,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    )
    #expect(!result.evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    #expect(result.evaluation.noisePatterns.isEmpty)
}

@Test func digestBuildIsDeterministicWithRules() throws {
    let entries = try BootFixtureEntries.loadBootLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let context = ContainerContext(
        containerName: "hello",
        image: "docker.io/library/alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
    )
    let window = DigestWindow(description: "logs before container exit")
    let builder = LogDigestBuilder()
    let renderer = PromptRenderer()

    let first = renderer.render(builder.buildWithRules(entries: entries, context: context, window: window).digest)
    let second = renderer.render(builder.buildWithRules(entries: entries, context: context, window: window).digest)
    #expect(first == second)
    #expect(first.data(using: .utf8) == second.data(using: .utf8))
}
