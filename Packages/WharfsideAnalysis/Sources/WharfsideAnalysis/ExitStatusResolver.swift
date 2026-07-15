import Foundation

/// Merges runtime (XPC) exit evidence with boot-log fallback. Runtime wins when both exist.
public enum ExitStatusResolver {
  private static let bootParser = BootLogExitStatusParser()

  public static func resolve(runtime: ExitStatus, bootEntries: [LogEntry]) -> ExitStatus {
    if case .known = runtime {
      return runtime
    }

    switch runtime {
    case .unavailable(.runtimeGone), .unavailable(.noEvidence):
      return bootParser.parse(bootEntries: bootEntries)
    case .unavailable(.stillRunning), .unavailable(.ambiguousEvidence):
      return runtime
    case .known:
      return runtime
    }
  }
}
