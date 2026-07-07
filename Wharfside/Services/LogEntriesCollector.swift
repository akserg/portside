// Services/LogEntriesCollector.swift
// Issue 1.7 — cold log fetch when the Logs tab buffer is empty.

import Foundation
import WharfsideAnalysis

enum LogEntriesCollector {
    /// Collects a snapshot of container logs via `logStream` when the in-memory buffer is empty.
    ///
    /// `logStream` polls indefinitely for stopped containers (it never finishes on its own).
    /// We cap wall-clock collection and cancel the consumer so diagnosis cannot hang after the
    /// first chunk is drained.
    static func collect(
        from service: any ContainerServicing,
        containerID: String,
        maxDuration: Duration = .seconds(2)
    ) async -> [LogEntry] {
        final class Collector: @unchecked Sendable {
            var buffer = LogRingBuffer()
        }
        let collector = Collector()

        let consumeTask = Task {
            let stream = service.logStream(id: containerID, source: nil)
            do {
                for try await chunk in stream {
                    collector.buffer.append(chunk: chunk)
                }
            } catch {
                DiagnosisLog.info("log collect stream ended for \(containerID): \(error.localizedDescription)")
            }
        }

        try? await Task.sleep(for: maxDuration)
        consumeTask.cancel()
        _ = await consumeTask.value

        let entries = collector.buffer.recentEntries(within: .seconds(3600))
        DiagnosisLog.info("collected \(entries.count) log entries for \(containerID)")
        return entries
    }
}
