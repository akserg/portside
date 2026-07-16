// Services/LogEntriesCollector.swift
// Issue 1.7 — cold log fetch for diagnosis evidence assembly.

import Foundation
import WharfsideAnalysis

enum LogEntriesCollector {
    /// Per-phase wall-clock cap for cold log collection.
    ///
    /// Stdio and boot are collected as separate phases. Worst case total wait is ~4 s
    /// (2 s stdio + 2 s boot) when both must be cold-fetched.
    static let phaseDuration: Duration = .seconds(2)

    /// Assembles the canonical diagnosis evidence window for a container.
    ///
    /// - **stdio:** buffered `recentEntries` when the Logs tab already holds stdio;
    ///   otherwise a cold stdio fetch.
    /// - **boot:** always a cold fetch — never gated on empty stdio, never taken from the
    ///   display buffer's source filter. Feeds the shared final-cycle window (I5) for
    ///   MatchContext, digest BOOT_LOG appendix, and exit-status parsing.
    ///
    /// `logStream` polls indefinitely for stopped containers (it never finishes on its own).
    /// Each phase caps wall-clock collection and cancels the consumer so diagnosis cannot hang
    /// after the first chunk is drained.
    static func assembleEvidence(
        from service: any ContainerServicing,
        containerID: String,
        buffered: [LogEntry],
        maxDuration: Duration = .seconds(2)
    ) async -> [LogEntry] {
        let bufferedStdio = buffered.filter { $0.source == .stdio }
        let stdio: [LogEntry]
        if bufferedStdio.isEmpty {
            stdio = await collectPhase(
                from: service,
                containerID: containerID,
                source: .stdio,
                maxDuration: maxDuration
            )
        } else {
            stdio = bufferedStdio
            DiagnosisLog.info("using \(stdio.count) buffered stdio entries for \(containerID)")
        }

        let boot = await collectPhase(
            from: service,
            containerID: containerID,
            source: .boot,
            maxDuration: maxDuration
        )
        DiagnosisLog.info("collected \(boot.count) boot log entries for \(containerID)")

        if stdio.isEmpty {
            return boot
        }
        if boot.isEmpty {
            return stdio
        }
        return stdio + boot
    }

    /// Cold-fetches both sources when the in-memory buffer is empty (no Logs interaction).
    static func collect(
        from service: any ContainerServicing,
        containerID: String,
        maxDuration: Duration = .seconds(2)
    ) async -> [LogEntry] {
        await assembleEvidence(
            from: service,
            containerID: containerID,
            buffered: [],
            maxDuration: maxDuration
        )
    }

    private static func collectPhase(
        from service: any ContainerServicing,
        containerID: String,
        source: LogSource,
        maxDuration: Duration
    ) async -> [LogEntry] {
        final class Collector: @unchecked Sendable {
            var buffer = LogRingBuffer()
        }
        let collector = Collector()

        let consumeTask = Task {
            let stream = service.logStream(id: containerID, source: source)
            do {
                for try await chunk in stream {
                    collector.buffer.append(chunk: chunk)
                }
            } catch {
                DiagnosisLog.info(
                    "log collect stream ended for \(containerID) (\(source.rawValue)): "
                        + error.localizedDescription
                )
            }
        }

        try? await Task.sleep(for: maxDuration)
        consumeTask.cancel()
        _ = await consumeTask.value

        // Keep only the requested source — a mis-labeled chunk from a mock/stub must not
        // leak into the other phase's evidence.
        return collector.buffer.recentEntries(within: .seconds(3600))
            .filter { $0.source == source }
    }
}
