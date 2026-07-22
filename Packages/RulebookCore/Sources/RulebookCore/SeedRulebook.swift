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
                noEvidencePrecheck,
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
        references: [
            RuleReference(
                type: .runtimeSource,
                title: "gracefulStopContainer races wait against kill(signal)→sleep(timeout)→kill(SIGKILL), synthesizing exit 137 on escalation; stop signal defaults to SIGTERM",
                url: "https://github.com/apple/container/blob/ee848e3ebfd7c73b04dd419683be54fb450b8779/Sources/Services/RuntimeLinux/Server/RuntimeService.swift#L1214-L1246",
                runtimeVersions: ["1.0.0"]
            ),
            RuleReference(
                type: .runtimeSource,
                title: "containerWait resolves ExitStatus through the live container state; after stop's handleContainerExit cleanup the client is unreachable, so status is only observable during the stopping window",
                url: "https://github.com/apple/container/blob/ee848e3ebfd7c73b04dd419683be54fb450b8779/Sources/Services/ContainerAPIService/Server/Containers/ContainersService.swift#L675-L698",
                runtimeVersions: ["1.0.0"]
            ),
        ],
        conclusionCategory: "stopped",
        conclusionSummary: "Container stopped via SIGTERM/SIGKILL (orderly stop); "
            + "boot log shows signal 15 → grace period → signal 9 → exit 137."
    ))

    /// Evidence-free exit: boot-log-only, no error content, no stop signature, non-zero
    /// exit. Kept in the seed so a rejected bundled rulebook still fails closed on the
    /// class B8 targets — otherwise a signature/malformed fallback would leak these
    /// digests back to the model (the exact timeout/fabrication B8 prevents). Mirrors the
    /// bundled Rulebook.json entry byte-for-byte so seed == bundled stays invariant.
    static let noEvidencePrecheck = Rule.precheck(PrecheckRule(
        id: "precheck.no-evidence",
        criteria: MatchCriteria(
            sources: ["bootLogOnly"],
            maxErrorCount: 0,
            excludesLogPatterns: [#"sending signal 15 to process"#],
            excludesExitCodes: [0]
        ),
        emitsFact: "EVIDENCE: container exited without writing any application output",
        references: [
            RuleReference(
                type: .observed,
                title: "A boot-log-only container exit with no application errors or orderly-stop signal can leave no application output to analyze"
            ),
        ],
        conclusionCategory: "unknown",
        conclusionSummary: "The container exited{exit_status} without writing any application output — "
            + "there is nothing in the logs to analyze. If this exit is unexpected, "
            + "check whether the command writes errors to stdout/stderr.",
        conclusionConfidence: "low",
        conclusionActions: [
            "Run `container logs {container}` to confirm no output was produced",
            "If unexpected, run the container's command manually to see its error output",
        ]
    ))

    /// Fires only when the pattern hits a log line (can appear multiple times per cycle).
    static let vminitdMemoryThresholdNoise = Rule.noise(NoiseRule(
        id: "noise.vminitd-memory-threshold",
        criteria: .always,
        linePattern: #"vminitd memory threshold exceeded"#,
        references: [
            RuleReference(
                type: .observed,
                title: "vminitd memory threshold exceeded fires on every VM boot regardless of the container exit outcome"
            ),
        ]
    ))
}
