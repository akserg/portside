import Foundation
import Testing
@testable import WharfsideAnalysis

/// B8.2 — stdio-primary containers must still carry boot final-cycle evidence in the digest.
@Test func stdioPrimaryFixtureYieldsBootAppendixAndSkipsNoEvidence() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "stdio_primary_loses_boot_evidence.log")
    let exit = ExitStatusResolver.resolve(
        runtime: .unavailable(reason: .runtimeGone),
        bootEntries: entries
    )
    #expect(exit == .known(1, source: .bootLog))

    let context = ContainerContext(
        containerName: "diag-loud",
        image: "docker.io/library/alpine:latest",
        exitStatus: exit,
        restartCount: 0
    )
    let match = MatchContextBuilder.make(entries: entries, context: context)
    #expect(match.source == "stdioWithBootFallback")
    #expect(match.exitCode == 1)

    let result = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    )
    let rendered = PromptRenderer().render(result.digest)

    #expect(rendered.contains("EXIT_CODE: 1 (from boot log)"))
    #expect(rendered.contains("BOOT_LOG (runtime init, usually not the app's crash cause):"))
    #expect(rendered.contains("ERROR boom"))
    #expect(result.evaluation.matchedRuleIDs.contains("noise.vminitd-memory-threshold"))
    // Discovery 4: sources gate keeps no-evidence off stdio-primary digests even with exit 1.
    #expect(result.evaluation.precheckConclusion == nil)
    #expect(!result.evaluation.matchedRuleIDs.contains("precheck.no-evidence"))
}
