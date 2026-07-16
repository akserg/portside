import Foundation
import Testing
@testable import WharfsideAnalysis

struct BootLogExitStatusParserTests {
  private let parser = BootLogExitStatusParser()

  @Test func userStopBootFixtureYieldsKnown137() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_user_stop_boot.log")
    let status = parser.parse(bootEntries: entries)
    #expect(status == .known(137, source: .bootLog))
  }

  @Test func stopTimeoutFlagshipResolvesFinalLifecycleCycle() throws {
    let full = try FixtureLoader.loadLog(named: "stop_timeout_misdiagnosed_as_oom.log")
    let logParser = LogParser()
    let allBoot = logParser.parse(text: full).map {
      LogEntry(
        timestamp: $0.timestamp,
        level: $0.level,
        message: $0.message,
        raw: $0.raw,
        source: .boot
      )
    }
    let canonical = try LabeledFixtureLoader.loadLog(named: "exit_status_user_stop_boot.log")
    let fromFull = parser.parse(bootEntries: allBoot)
    let fromCanonical = parser.parse(bootEntries: canonical)
    #expect(fromFull == .known(137, source: .bootLog))
    #expect(fromCanonical == .known(137, source: .bootLog))
  }

  @Test func multicycleHelloFixtureYieldsKnown137FromFinalCycle() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_multicycle_hello_boot.log")
    #expect(parser.parse(bootEntries: entries) == .known(137, source: .bootLog))
  }

  /// B8 discovery 1: a `sh -c 'exit 1'` container produces an unambiguous single
  /// `status: 1 managed process exit` in its final cycle but no SIGTERM/SIGKILL sequence.
  /// The parser currently requires the signal sequence, so this resolves to
  /// `.ambiguousEvidence` instead of `.known(1, .bootLog)` — the exit-status gap.
  /// Wrapped in `withKnownIssue` so the suite stays green for bisect; commit 2 (fix 4a)
  /// removes the wrapper.
  @Test func exitOneNoOutputBootFixtureResolvesKnownOne() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_no_output_misdiagnosed_or_timeout.log")
    #expect(parser.parse(bootEntries: entries) == .known(1, source: .bootLog))
  }

  @Test func cycleSegmenterUsesTerminalExitAsBoundary() {
    let lines = [
      "warning vminitd: vminitd memory threshold exceeded",
      "info vminitd: id: hello, pid: 110 started managed process",
      "info vminitd: id: hello, status: 0 managed process exit",
      "warning vminitd: vminitd memory threshold exceeded",
      "info vminitd: id: hello, pid: 109 started managed process",
      "info vminitd: id: hello sending signal 15 to process 109",
      "info vminitd: id: hello, status: 137 managed process exit",
      "info vminitd: id: hello closing relay for StandardIO stdout"
    ]
    let segment = BootLogCycleSegmenter.finalCycleLines(from: lines)
    #expect(segment.count == 5)
    #expect(segment.first?.contains("memory threshold exceeded") == true)
    #expect(segment.contains { $0.contains("pid: 109") })
    #expect(segment.contains { $0.contains("status: 137") })
    #expect(segment.last?.contains("closing relay") == true)
    #expect(!segment.contains { $0.contains("pid: 110") })
    #expect(!segment.contains { $0.contains("status: 0") })
  }

  @Test func cycleSegmenterIncludesPreambleBeforeStartedManagedProcess() {
    let lines = [
      "warning vminitd: vminitd memory threshold exceeded",
      "info vminitd: id: hello, pid: 109 started managed process",
      "info vminitd: id: hello sending signal 15 to process 109",
      "info vminitd: id: hello sending signal 9 to process 109",
      "info vminitd: id: hello, status: 137 managed process exit"
    ]
    let segment = BootLogCycleSegmenter.finalCycleLines(from: lines)
    #expect(segment.first?.contains("memory threshold exceeded") == true)
    #expect(segment.contains { $0.contains("started managed process") })
  }

  @Test func noEvidenceWhenBootLacksStopSignature() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_no_evidence_boot.log")
    #expect(parser.parse(bootEntries: entries) == .unavailable(reason: .noEvidence))
  }

  @Test func multiTerminalBootResolvesMostRecentCycleExit() throws {
    // Each `status: N managed process exit` is a cycle terminal, so two back-to-back
    // status lines belong to separate cycles. Final-cycle scoping resolves the most
    // recent lifecycle's exit (here, `status: 0`) rather than failing closed.
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_ambiguous_boot.log")
    #expect(parser.parse(bootEntries: entries) == .known(0, source: .bootLog))
  }

  @Test func parseFinalCycleFailsClosedOnTwoStatusLinesInOneSegment() {
    // Genuine within-cycle ambiguity (I6): two status lines with no intervening terminal
    // boundary in a single segment still fails closed after the 4a fix.
    let segment = [
      "info vminitd: id: x sending signal 15 to process 1",
      "info vminitd: id: x, status: 137 managed process exit",
      "info vminitd: id: x, status: 0 managed process exit"
    ]
    #expect(parser.parseFinalCycle(lines: segment) == .unavailable(reason: .ambiguousEvidence))
  }

  @Test func hostileStdioCannotForgeExitEvidence() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_hostile_stdio.log")
    #expect(parser.parse(bootEntries: entries) == .unavailable(reason: .noEvidence))
  }

  @Test func singleStatusWithoutSignalSequenceResolvesExitCode() throws {
    // B8 (fix 4a): a lone unambiguous terminal status line resolves the exit code even
    // without the SIGTERM/SIGKILL sequence. Ambiguity (multiple status lines) still
    // fails closed — see `ambiguousWhenMultipleStopSequences`.
    let entries = [
      LogEntry(
        timestamp: nil,
        level: .info,
        message: "status: 137 managed process exit",
        raw: "status: 137 managed process exit",
        source: .boot
      )
    ]
    #expect(parser.parse(bootEntries: entries) == .known(137, source: .bootLog))
  }

  @Test func resolverPrefersRuntimeOverBootLog() {
    let bootEntries = [
      LogEntry(
        timestamp: nil,
        level: .info,
        message: "status: 1 managed process exit",
        raw: "info vminitd: sending signal 15 to process 1",
        source: .boot
      ),
      LogEntry(
        timestamp: nil,
        level: .info,
        message: "status: 1 managed process exit",
        raw: "info vminitd: sending signal 9 to process 1",
        source: .boot
      ),
      LogEntry(
        timestamp: nil,
        level: .info,
        message: "status: 1 managed process exit",
        raw: "info vminitd: status: 1 managed process exit",
        source: .boot
      )
    ]
    let runtime = ExitStatus.known(42, source: .runtime)
    let resolved = ExitStatusResolver.resolve(runtime: runtime, bootEntries: bootEntries)
    #expect(resolved == .known(42, source: .runtime))
  }

  @Test func resolverFallsBackToBootLogOnRuntimeGone() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_user_stop_boot.log")
    let runtime = ExitStatus.unavailable(reason: .runtimeGone)
    let resolved = ExitStatusResolver.resolve(runtime: runtime, bootEntries: entries)
    #expect(resolved == .known(137, source: .bootLog))
  }

  @Test func promptRendererLabelsBootLogProvenance() throws {
    let entries = try LabeledFixtureLoader.loadLog(named: "exit_status_user_stop_boot.log")
    let digest = LogDigestBuilder().build(
      entries: entries,
      context: ContainerContext(
        containerName: "hello",
        image: "alpine:latest",
        exitStatus: .known(137, source: .bootLog),
        restartCount: 0
      ),
      window: DigestWindow(description: "fixture")
    )
    let rendered = PromptRenderer().render(digest)
    #expect(rendered.contains("EXIT_CODE: 137 (from boot log)"))
  }
}
