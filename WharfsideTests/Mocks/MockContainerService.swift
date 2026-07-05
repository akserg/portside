// WharfsideTests/Mocks/MockContainerService.swift

import Foundation
@testable import Wharfside

final class MockContainerService: ContainerServicing, @unchecked Sendable {
    var summaries: [ContainerSummary] = []
    var detail = ContainerDetail(
        id: "mock",
        image: "alpine",
        status: .stopped,
        command: ["/bin/sh"],
        environmentCount: 0,
        mountCount: 0,
        publishedPortCount: 0,
        networkCount: 0,
        startedAt: nil
    )
    var stats = ContainerStats(
        id: "mock",
        memoryUsageBytes: nil,
        memoryLimitBytes: nil,
        cpuUsageMicroseconds: nil,
        networkRxBytes: nil,
        networkTxBytes: nil,
        blockReadBytes: nil,
        blockWriteBytes: nil,
        processCount: nil
    )
    var execResult = ExecResult(exitCode: 0, stdout: "", stderr: "")

    private(set) var listCallCount = 0
    private(set) var startCallCount = 0
    var listError: Error?
    var startError: Error?

    func list() async throws -> [ContainerSummary] {
        listCallCount += 1
        if let listError { throw listError }
        return summaries
    }

    func get(id: String) async throws -> ContainerDetail {
        detail
    }

    func create(id: String, image: String, command: [String]) async throws {}

    func start(id: String) async throws {
        startCallCount += 1
        if let startError { throw startError }
    }

    func stop(id: String, timeout: TimeInterval) async throws {}

    func kill(id: String, signal: String) async throws {}

    func delete(id: String, force: Bool) async throws {}

    func stats(id: String) async throws -> ContainerStats {
        stats
    }

    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LogChunk(source: .stdio, data: Data("mock\n".utf8)))
            continuation.finish()
        }
    }

    func exec(id: String, command: [String]) async throws -> ExecResult {
        execResult
    }
}
