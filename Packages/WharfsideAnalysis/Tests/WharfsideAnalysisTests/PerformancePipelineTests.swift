import Foundation
import Testing
@testable import WharfsideAnalysis

/// 100k-line stress tests — serialized so they never run two at once (each allocates ~10 MB).
@Suite(.serialized)
struct PerformancePipelineTests {
    private static func syntheticLog(lineCount: Int, level: String, message: (Int) -> String) -> String {
        var lines: [String] = []
        lines.reserveCapacity(lineCount)
        for index in 0..<lineCount {
            let second = String(format: "%02d", index % 60)
            lines.append("2024-01-01T00:00:\(second)Z \(level): \(message(index))")
        }
        return lines.joined(separator: "\n")
    }

    @Test func digestRespectsTokenBudget() {
        let text = Self.syntheticLog(lineCount: 100_000, level: "ERROR") { index in
            let host = "10.0.\(index % 255).\(index % 100)"
            return "failure \(index) host=\(host)"
        }

        let context = ContainerContext(
            containerName: "noisy",
            image: "app:latest",
            exitStatus: .known(137, source: .runtime),
            restartCount: 5
        )
        let digest = LogDigestBuilder(tokenBudget: 1500).build(
            logText: text,
            context: context,
            window: DigestWindow(description: "full log")
        )

        #expect(digest.estimatedTokens <= 1500)
        #expect(digest.firstError != nil)
        #expect(digest.counts["ERROR", default: 0] > 0)
    }

    @Test func noisyLogDigestCompletesWithinTimeLimit() {
        let text = Self.syntheticLog(lineCount: 100_000, level: "INFO") { index in
            "tick \(index)"
        }
        let builder = LogDigestBuilder()

        let start = ContinuousClock.now
        let context = ContainerContext(
            containerName: "perf",
            image: "app:latest",
            exitStatus: .unavailable(reason: .noEvidence),
            restartCount: 0
        )
        _ = builder.build(
            logText: text,
            context: context,
            window: DigestWindow(description: "full log")
        )
        let elapsed = start.duration(to: ContinuousClock.now)

        // Guard against catastrophic regression; GA macOS runners vary widely (often 5–10s).
        #if DEBUG
        #expect(elapsed < .seconds(6))
        #else
        #expect(elapsed < .seconds(12))
        #endif
    }
}
