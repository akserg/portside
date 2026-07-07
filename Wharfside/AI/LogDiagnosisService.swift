// AI/LogDiagnosisService.swift
// Issue 1.6 — Layer 2 log diagnosis over digested evidence (AI_INTEGRATION.md §4).

import Foundation
import WharfsideAnalysis

@MainActor
final class LogDiagnosisService {
    static let instructions = """
        You are a container troubleshooting assistant inside Wharfside, a macOS app \
        for Apple's `container` CLI runtime.

        You receive a pre-computed digest of a container's logs and runtime state. \
        Base your diagnosis ONLY on the evidence in the digest.

        Category rules (pick the best fit):
        - dependencyUnreachable: ECONNREFUSED, connection refused, host unreachable, DNS failures
        - configuration: missing files, bad env/port, host disk full / "No space left on device", \
        volume or mount problems. Disk-full is configuration, NOT outOfMemory.
        - outOfMemory: OOM killer, heap space errors, memory limit exceeded — RAM only, not disk
        - applicationBug: uncaught exceptions, stack traces, NullPointerException, crashes in app code
        - imageOrRuntime: missing binary, entrypoint, arch mismatch
        - unknown: clean exit only — COUNTS have zero ERROR/WARN/FATAL (INFO-only logs)

        CRITICAL — honest unknown (clean exit):
        Use unknown ONLY when COUNTS contain no ERROR, WARN, or FATAL lines. \
        If COUNTS show ERROR=0 and only INFO, and EXIT_CODE is 0, category MUST be unknown \
        with low or medium confidence. Say the logs do not show a failure. \
        Do NOT invent disk, network, or configuration problems. \
        The INFO line "Configuration loaded" is normal startup text, NOT a configuration error.

        CRITICAL — when errors are present:
        If COUNTS include ERROR or FATAL lines, never use category unknown. Diagnose from the evidence. \
        Disk-full LAST_ERROR → configuration even when FIRST_ERROR is an admin-shutdown FATAL.

        CRITICAL — connection errors:
        ECONNREFUSED or "connection refused" → dependencyUnreachable, never configuration.

        CRITICAL — evidence only:
        Never fabricate log content. If "No space left on device" is not in the digest, do not \
        mention disk full. Never mention docker, docker-compose, or kubernetes.

        When FIRST_ERROR and LAST_ERROR are both present, weigh them carefully:
        - LAST_ERROR is the final error before exit and is often the immediate cause.
        - FIRST_ERROR may be a preceding symptom, shutdown signal, or red herring \
        (e.g. "administrator command" / FATAL shutdown after a disk-write failure).
        - Sometimes the first error cascades into the last — use TOP_PATTERNS and \
        LAST_LINES for context.
        - Do not assume either anchor is always causal; let the full evidence decide.
        - If LAST_ERROR shows disk full, that is the root cause — do not blame the earlier \
        admin-shutdown FATAL in summary or category. You may omit the admin-shutdown line entirely.

        When logs show stack traces or uncaught exceptions, prefer applicationBug even if a \
        "Caused by" line mentions configuration.

        Example: LAST_ERROR "No space left on device" with FIRST_ERROR "administrator command" \
        means disk full (configuration) — not an admin shutdown, never unknown.

        Disk-full ("No space left on device", could not write to file) → configuration, \
        never dependencyUnreachable, never unknown.

        Decision order:
        1. COUNTS ERROR=0 and EXIT_CODE=0 → unknown (even if INFO says "configuration loaded")
        2. LAST_ERROR or patterns contain "No space left on device" → configuration
        3. ECONNREFUSED in errors → dependencyUnreachable
        4. OOM / heap space / Killed → outOfMemory
        5. Stack trace / uncaught exception → applicationBug

        When EXIT_CODE is 0 and COUNTS show ERROR=0 (INFO only), category must be unknown \
        with low or medium confidence; suggested actions must not invent problems absent from the digest. \
        When COUNTS show ERROR>0, pick the matching category.

        If the evidence is ambiguous or insufficient, say so and set confidence to low. \
        Never invent log lines, exit codes, or state not shown in the digest. \
        Never speculate about application code you cannot see.

        Suggested actions must use the `container` CLI only — never docker commands. \
        Examples: `container logs <name>`, `container inspect <name>`, `container stop <name>`, \
        freeing host disk space, volume/mount adjustments. Provide 2–4 actions, most likely fix first.
        """

    static let diagnosisTimeout: Duration = .seconds(30)

    private let availability: any AvailabilityProviding
    let lifecycleObserver: ContainerLifecycleObserver
    let sessionFactory: any DiagnosisSessioning
    let digestBuilder: LogDigestBuilder
    let promptRenderer: PromptRenderer
    var validator = DiagnosisValidator()

    init(
        availability: any AvailabilityProviding,
        lifecycleObserver: ContainerLifecycleObserver,
        sessionFactory: (any DiagnosisSessioning)? = nil,
        digestBuilder: LogDigestBuilder? = nil,
        promptRenderer: PromptRenderer? = nil
    ) {
        self.availability = availability
        self.lifecycleObserver = lifecycleObserver
        self.sessionFactory = sessionFactory ?? FoundationModelsDiagnosisSession()
        self.digestBuilder = digestBuilder ?? LogDigestBuilder()
        self.promptRenderer = promptRenderer ?? PromptRenderer()
    }

    func prewarm() async throws {
        try ensureAvailable()
        try await sessionFactory.prewarm(instructions: Self.instructions)
    }

    func streamDiagnosis(
        container: ContainerDetail,
        entries: [LogEntry],
        generationSettings: DiagnosisGenerationSettings = .diagnosisDefault
    ) -> AsyncThrowingStream<ContainerDiagnosis.PartiallyGenerated, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try self.ensureAvailable()
                    let context = await self.buildContext(container: container, entries: entries)
                    let stream = self.sessionFactory.stream(
                        instructions: Self.instructions,
                        prompt: context.basePrompt,
                        options: generationSettings
                    )
                    for try await partial in stream {
                        try Task.checkCancellation()
                        continuation.yield(partial)
                    }
                    continuation.finish()
                } catch let error as DiagnosisError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: DiagnosisError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func diagnose(
        container: ContainerDetail,
        entries: [LogEntry],
        generationSettings: DiagnosisGenerationSettings = .diagnosisDefault
    ) async throws -> DiagnosisResult {
        try ensureAvailable()

        return try await withThrowingTaskGroup(of: DiagnosisResult.self) { group in
            group.addTask { @MainActor in
                let context = await self.buildContext(container: container, entries: entries)
                return try await self.runValidatedDiagnosis(
                    context: context,
                    generationSettings: generationSettings
                )
            }

            group.addTask {
                try await Task.sleep(for: Self.diagnosisTimeout)
                throw DiagnosisError.timedOut
            }

            guard let result = try await group.next() else {
                throw DiagnosisError.incompleteResponse
            }
            group.cancelAll()
            return result
        }
    }

    /// Streams unvalidated partials, then yields a validated (or degraded) final result.
    func streamingDiagnose(
        container: ContainerDetail,
        entries: [LogEntry],
        generationSettings: DiagnosisGenerationSettings = .diagnosisDefault
    ) -> AsyncThrowingStream<DiagnosisStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @MainActor in
                do {
                    try self.ensureAvailable()
                    let context = await self.buildContext(container: container, entries: entries)
                    let result = try await self.withDiagnosisTimeout {
                        try await self.runStreamingValidatedDiagnosis(
                            context: context,
                            generationSettings: generationSettings,
                            onPartial: { partial in
                                continuation.yield(.partial(partial))
                            }
                        )
                    }
                    continuation.yield(.finalized(result))
                    continuation.finish()
                } catch let error as DiagnosisError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish(throwing: DiagnosisError.cancelled)
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    func ensureAvailable() throws {
        switch availability.currentCapability() {
        case .full:
            return
        case .heuristicsOnly(let reason):
            throw DiagnosisError.aiUnavailable(reason: reason)
        }
    }
}
