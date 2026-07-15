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
        context: ContainerContext(
            containerName: "quiet",
            image: "app:1",
            exitStatus: .known(0, source: .runtime),
            restartCount: 0
        ),
        window: DigestWindow(description: "full log")
    )

    #expect(digest.firstError == nil)
    #expect(digest.lastError == nil)
    #expect(digest.counts["ERROR", default: 0] == 0)
    #expect(digest.counts["INFO", default: 0] == 3)
}

@Test func digestBuildIsDeterministic() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let context = ContainerContext(
        containerName: "db",
        image: "postgres:16",
        exitStatus: .known(1, source: .runtime),
        restartCount: 1
    )
    let window = DigestWindow(description: "last 5 minutes before exit")
    let builder = LogDigestBuilder()

    let first = PromptRenderer().render(builder.build(logText: text, context: context, window: window))
    let second = PromptRenderer().render(builder.build(logText: text, context: context, window: window))

    #expect(first == second)
    #expect(first.data(using: .utf8) == second.data(using: .utf8))
}

@Test func parserSkipsBlankLines() throws {
    let text = try FixtureLoader.loadLog(named: "blank_lines.log")
    let entries = LogParser().parse(text: text)

    #expect(entries.count == 3)
    #expect(entries.allSatisfy { $0.level == .info })
}

@Test func parserNeverDropsMeaningfulLines() {
    let entries = LogParser().parse(lines: [
        "not json {{{{",
        "level=broken msg=",
        "(\"\")"
    ])
    #expect(entries.count == 3)
}

@Test func postgresCrashParsesFiveEntries() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let entries = LogParser().parse(text: text)

    #expect(entries.count == 5)
}

@Test func digestCountsMatchParsedEntryCount() throws {
    let manifest = try FixtureLoader.loadManifest()
    let parser = LogParser()
    let builder = LogDigestBuilder()

    for entry in manifest.fixtures {
        let text = try FixtureLoader.loadLog(named: entry.file)
        let parsed = parser.parse(text: text)
        let context = ContainerContext(
            containerName: "test",
            image: "img:latest",
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0
        )
        let digest = builder.build(
            logText: text,
            context: context,
            window: DigestWindow(description: "full log")
        )

        let countSum = digest.counts.values.reduce(0, +)
        #expect(parsed.count == countSum, "\(entry.file): parsed=\(parsed.count) counts=\(countSum)")
    }
}

@Test func noPatternHasEmptyTemplate() throws {
    let manifest = try FixtureLoader.loadManifest()
    let parser = LogParser()
    let clusterer = PatternClusterer()

    for entry in manifest.fixtures {
        let text = try FixtureLoader.loadLog(named: entry.file)
        let patterns = clusterer.cluster(entries: parser.parse(text: text))
        for pattern in patterns {
            #expect(pattern.template != "{empty}", "\(entry.file)")
        }
    }
}

@Test func postgresLevelsMapToExpectedSeverity() {
    let cases: [(String, LogLevel)] = [
        ("PANIC", .error),
        ("FATAL", .error),
        ("ERROR", .error),
        ("WARNING", .warn),
        ("NOTICE", .info),
        ("LOG", .info),
        ("INFO", .info),
        ("DEBUG", .debug)
    ]

    for (token, expected) in cases {
        #expect(LogLevel.fromPostgres(token) == expected, "postgres level \(token)")
    }
}

@Test func postgresDiskFullLineIsError() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let entries = LogParser().parse(text: text)
    let diskFull = entries.last

    #expect(diskFull?.level == .error)
    #expect(diskFull?.raw.contains("No space left on device") == true)
}

@Test func postgresCrashDigestSurfacesFirstAndLastError() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let digest = LogDigestBuilder().build(
        logText: text,
        context: ContainerContext(
            containerName: "db",
            image: "postgres:16",
            exitStatus: .known(1, source: .runtime),
            restartCount: 0
        ),
        window: DigestWindow(description: "full fixture log")
    )
    let rendered = PromptRenderer().render(digest)

    #expect(digest.firstError?.contains("administrator command") == true)
    #expect(digest.lastError?.contains("No space left on device") == true)
    #expect(rendered.contains("FIRST_ERROR:"))
    #expect(rendered.contains("LAST_ERROR:"))
    #expect(!rendered.contains("{empty}"))
    #expect(digest.counts.values.reduce(0, +) == 5)
}

@Test func singleErrorDigestEmitsBothErrorSections() throws {
    let text = try FixtureLoader.loadLog(named: "single_line.log")
    let digest = LogDigestBuilder().build(
        logText: text,
        context: ContainerContext(
            containerName: "app",
            image: "app:1",
            exitStatus: .known(0, source: .runtime),
            restartCount: 0
        ),
        window: DigestWindow(description: "full log")
    )
    let rendered = PromptRenderer().render(digest)

    #expect(digest.firstError == nil)
    #expect(digest.lastError == nil)
    #expect(!rendered.contains("FIRST_ERROR:"))
    #expect(!rendered.contains("LAST_ERROR:"))

    let errorText = "2024-01-01T00:00:00Z ERROR: boom"
    let errorDigest = LogDigestBuilder().build(
        logText: errorText,
        context: ContainerContext(
            containerName: "app",
            image: "app:1",
            exitStatus: .known(1, source: .runtime),
            restartCount: 0
        ),
        window: DigestWindow(description: "full log")
    )
    let errorRendered = PromptRenderer().render(errorDigest)

    #expect(errorDigest.firstError == errorDigest.lastError)
    #expect(errorRendered.contains("FIRST_ERROR:"))
    #expect(errorRendered.contains("LAST_ERROR:"))
}

@Test func promptRendererProducesLabeledSections() throws {
    let text = try FixtureLoader.loadLog(named: "postgres_crash.log")
    let digest = LogDigestBuilder().build(
        logText: text,
        context: ContainerContext(
            containerName: "db",
            image: "postgres:16",
            exitStatus: .known(1, source: .runtime),
            restartCount: 0
        ),
        window: DigestWindow(description: "last 5 minutes before exit")
    )
    let rendered = PromptRenderer().render(digest)

    #expect(rendered.contains("CONTAINER: db"))
    #expect(rendered.contains("FIRST_ERROR:"))
    #expect(rendered.contains("LAST_ERROR:"))
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
