import Foundation
import Testing
@testable import WharfsideAnalysis

@Test func manifestFixturesMatchLevelDistribution() throws {
    let manifest = try FixtureLoader.loadManifest()
    let parser = LogParser()

    for entry in manifest.fixtures {
        let text = try FixtureLoader.loadLog(named: entry.file)
        let parsed = parser.parse(text: text)
        var actual: [String: Int] = [:]
        for line in parsed {
            actual[line.level.label, default: 0] += 1
        }

        for (level, expected) in entry.levelCounts {
            #expect(
                actual[level, default: 0] == expected,
                "\(entry.file): expected \(level)=\(expected), got \(actual[level, default: 0])"
            )
        }

        let expectedTotal = entry.levelCounts.values.reduce(0, +)
        let actualRelevant = entry.levelCounts.keys.reduce(0) { $0 + actual[$1, default: 0] }
        #expect(actualRelevant == expectedTotal, "\(entry.file) level count mismatch")
    }
}

@Test func nodeECONNREFUSEDCollapsesToSinglePattern() throws {
    let text = try FixtureLoader.loadLog(named: "node_econnrefused.log")
    let entries = LogParser().parse(text: text)
    let patterns = PatternClusterer().cluster(entries: entries)

    #expect(patterns.filter { $0.template.contains("ECONNREFUSED") }.count == 1)
    let refused = patterns.first { $0.template.contains("ECONNREFUSED") }
    #expect(refused?.count == 5)
}

@Test func jvmStackTraceMergesContinuationLines() throws {
    let text = try FixtureLoader.loadLog(named: "jvm_stacktrace.log")
    let entries = LogParser().parse(text: text)

    #expect(entries.count == 2)
    #expect(entries[1].level == .error)
    #expect(entries[1].message.contains("at com.example.app.Service.process"))
    #expect(entries[1].message.contains("Caused by:"))
}

@Test func silentExitDigestHasNoFirstError() throws {
    let text = try FixtureLoader.loadLog(named: "silent_exit.log")
    let digest = LogDigestBuilder().build(
        logText: text,
        context: ContainerContext(containerName: "quiet", image: "app:1", exitCode: 0, restartCount: 0),
        window: DigestWindow(description: "full log")
    )

    #expect(digest.firstError == nil)
    #expect(digest.counts["ERROR", default: 0] == 0)
    #expect(digest.counts["INFO", default: 0] == 3)
}

@Test func digestBuildIsDeterministic() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let context = ContainerContext(containerName: "db", image: "postgres:16", exitCode: 1, restartCount: 1)
    let window = DigestWindow(description: "last 5 minutes before exit")
    let builder = LogDigestBuilder()

    let first = PromptRenderer().render(builder.build(logText: text, context: context, window: window))
    let second = PromptRenderer().render(builder.build(logText: text, context: context, window: window))

    #expect(first == second)
    #expect(first.data(using: .utf8) == second.data(using: .utf8))
}

@Test func parserNeverDropsLines() {
    let text = """
    not json {{{{
    level=broken msg=
    \("")
    """
    let entries = LogParser().parse(text: text)
    #expect(entries.count == 3)
}

@Test func promptRendererProducesLabeledSections() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let digest = LogDigestBuilder().build(
        logText: text,
        context: ContainerContext(containerName: "db", image: "postgres:16", exitCode: 1, restartCount: 0),
        window: DigestWindow(description: "last 5 minutes before exit")
    )
    let rendered = PromptRenderer().render(digest)

    #expect(rendered.contains("CONTAINER: db"))
    #expect(rendered.contains("FIRST_ERROR:"))
    #expect(rendered.contains("TOP_PATTERNS:"))
    #expect(!rendered.contains("**"))
}

@Test func messageNormalizerReplacesVariableSegments() {
    let normalizer = MessageNormalizer()
    let template = normalizer.normalize(
        "connect ECONNREFUSED 127.0.0.1:5432 req=abc-123-def-456-789-abc-def123456789"
    )
    #expect(template.contains("{ip}:{port}") || template.contains("ECONNREFUSED"))
    #expect(!template.contains("127.0.0.1"))
}
