import Foundation

/// Splits vminitd boot logs into lifecycle cycles for exit-evidence extraction.
///
/// See `Docs/OBSERVED_STOP_SIGNATURE.md` — diagnosis asks why the container died
/// *most recently*, so evidence is scoped to the final cycle only.
enum BootLogCycleSegmenter {
  /// Observed once per init lifecycle in fixtures (`stop_timeout_misdiagnosed_as_oom.log`, report2).
  static let cycleStartMarker = "started managed process"

  /// Boot-source raw lines belonging to the most recent lifecycle cycle.
  static func finalCycleLines(from bootLines: [String]) -> [String] {
    guard let lastStart = bootLines.lastIndex(where: { $0.contains(cycleStartMarker) }) else {
      return bootLines
    }
    return Array(bootLines[lastStart...])
  }
}
