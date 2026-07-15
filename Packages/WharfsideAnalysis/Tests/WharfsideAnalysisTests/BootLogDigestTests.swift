import Foundation
import Testing
@testable import WharfsideAnalysis

@Test func bootNoiseContaminationDemotesBootLog() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "boot_noise_contamination.log")
    let context = ContainerContext(
        containerName: "crashy",
        image: "crashy:latest",
        exitStatus: .known(1, source: .runtime),
        restartCount: 0
    )
    let digest = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    ).digest
    let rendered = PromptRenderer().render(digest)

  #expect(digest.counts["ERROR", default: 0] == 1)
  #expect(digest.firstError?.contains("No space left on device") == true)
  #expect(digest.lastError?.contains("No space left on device") == true)
  #expect(digest.bootLines.count == 5)
  #expect(!digest.bootLines.contains { $0.localizedCaseInsensitiveContains("memory threshold") })
  #expect(digest.sourceNote == nil)
  #expect(rendered.contains("BOOT_LOG (runtime init, usually not the app's crash cause):"))
  #expect(!digest.topPatterns.contains { $0.template.localizedCaseInsensitiveContains("vminitd") })
  #expect(!digest.topPatterns.contains { $0.sampleRaw.localizedCaseInsensitiveContains("vminitd") })
  #expect(digest.lastError?.localizedCaseInsensitiveContains("vminitd") != true)
}

@Test func bootOnlyCrashPromotesBootToPrimary() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "boot_only_crash.log")
    let context = ContainerContext(
        containerName: "init-fail",
        image: "broken:latest",
        exitStatus: .known(1, source: .runtime),
        restartCount: 0
    )
    let digest = LogDigestBuilder().buildWithRules(
        entries: entries,
        context: context,
        window: DigestWindow(description: "logs before container exit")
    ).digest
    let rendered = PromptRenderer().render(digest)

  #expect(digest.sourceNote == "boot log only (no application output)")
  #expect(digest.bootLines.isEmpty)
  #expect(rendered.contains("SOURCE: boot log only (no application output)"))
  #expect(digest.firstError?.contains("rootfs mount failed") == true)
  #expect(digest.lastError?.contains("bootstrap aborted") == true)
  #expect(!rendered.contains("BOOT_LOG"))
}

@Test func existingFixturesStayByteIdenticalWithDefaultSource() throws {
    let manifest = try FixtureLoader.loadManifest()
    let builder = LogDigestBuilder()
    let renderer = PromptRenderer()
    let context = ContainerContext(
        containerName: "test",
        image: "img:latest",
        exitStatus: .known(1, source: .runtime),
        restartCount: 0
    )
    let window = DigestWindow(description: "full log")

    for entry in manifest.fixtures {
        let text = try FixtureLoader.loadLog(named: entry.file)
        let parsed = LogParser().parse(text: text)
        #expect(parsed.allSatisfy { $0.source == .stdio }, "\(entry.file) should default to stdio")

        let digest = builder.build(logText: text, context: context, window: window)
        let rendered = renderer.render(digest)
        #expect(digest.bootLines.isEmpty, "\(entry.file) should not emit boot lines")
        #expect(digest.sourceNote == nil, "\(entry.file) should not emit source note")
        #expect(!rendered.contains("BOOT_LOG"), "\(entry.file) should not render boot section")
        #expect(!rendered.contains("SOURCE:"), "\(entry.file) should not render source note")

        let again = renderer.render(builder.build(logText: text, context: context, window: window))
        #expect(rendered == again, "\(entry.file) digest must be deterministic")
        #expect(rendered.data(using: .utf8) == again.data(using: .utf8), "\(entry.file) byte-identical")
    }
}
