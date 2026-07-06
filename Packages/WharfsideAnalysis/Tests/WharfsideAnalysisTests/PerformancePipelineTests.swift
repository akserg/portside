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

        let digest = LogDigestBuilder(tokenBudget: 1500).build(
            logText: text,
            context: ContainerContext(containerName: "noisy", image: "app:latest", exitCode: 137, restartCount: 5),
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
        _ = builder.build(
            logText: text,
            context: ContainerContext(containerName: "perf", image: "app:latest", exitCode: nil, restartCount: 0),
            window: DigestWindow(description: "full log")
        )
        let elapsed = start.duration(to: ContinuousClock.now)

        // Debug builds are unoptimized; brief allows a generous margin off the 1s CI target.
        #expect(elapsed < .seconds(3))
    }
}
