import Foundation

/// Seed rulebook v0.1.0 — Layers 1–2 only (precheck + noise).
/// Prompt/validator kinds stay in the schema for forward compat but are not seeded here;
/// those layers remain hardcoded in the app (B3 scope).
public enum SeedRulebook {
    public static let version = "0.1.0"

    public static func make() -> Rulebook {
        Rulebook(
            version: version,
            minAppVersion: "0.1.1",
            rules: [
                stopEscalationPrecheck,
                vminitdMemoryThresholdNoise,
            ]
        )
    }

    public static var bundledJSON: Data {
        get throws {
            try JSONEncoder().encode(make())
        }
    }

    /// Orderly stop: SIGTERM → grace → SIGKILL → exit 137 in the final boot cycle.
    /// The signal sequence is the stop-request evidence — no Wharfside stop record required.
    static let stopEscalationPrecheck = Rule.precheck(PrecheckRule(
        id: "precheck.stop-escalation",
        criteria: MatchCriteria(
            exitCodes: [137],
            logPatterns: [
                #"sending signal 15 to process"#,
                #"sending signal 9 to process"#,
                #"status: 137 managed process exit"#,
            ]
        ),
        emitsFact: "TERMINATION: container stopped via SIGTERM then SIGKILL (orderly stop, exit 137)",
        suppressesCategories: ["outOfMemory", "crash"],
        conclusionCategory: "stopped",
        conclusionSummary: "Container stopped via SIGTERM/SIGKILL (orderly stop); "
            + "boot log shows signal 15 → grace period → signal 9 → exit 137."
    ))

    /// Fires only when the pattern hits a log line (can appear multiple times per cycle).
    static let vminitdMemoryThresholdNoise = Rule.noise(NoiseRule(
        id: "noise.vminitd-memory-threshold",
        criteria: .always,
        linePattern: #"vminitd memory threshold exceeded"#
    ))
}
