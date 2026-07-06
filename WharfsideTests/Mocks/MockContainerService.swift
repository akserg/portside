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
    private(set) var stopCallCount = 0
    private(set) var killCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastStartedID: String?
    private(set) var lastStoppedID: String?
    private(set) var lastKilledID: String?
    private(set) var lastDeletedID: String?
    private(set) var lastDeleteForce: Bool?

    var listError: Error?
    var startError: Error?
    var stopError: Error?
    var killError: Error?
    var deleteError: Error?
    var listDelay: Duration?

    func list() async throws -> [ContainerSummary] {
        listCallCount += 1
        if let listDelay {
            try await Task.sleep(for: listDelay)
        }
        if let listError { throw listError }
        return summaries
    }

    func get(id: String) async throws -> ContainerDetail {
        detail
    }

    func create(id: String, image: String, command: [String]) async throws {}

    func start(id: String) async throws {
        startCallCount += 1
        lastStartedID = id
        if let startError { throw startError }
    }

    func stop(id: String, timeout: TimeInterval) async throws {
        stopCallCount += 1
        lastStoppedID = id
        if let stopError { throw stopError }
    }

    func kill(id: String, signal: String) async throws {
        killCallCount += 1
        lastKilledID = id
        if let killError { throw killError }
    }

    func delete(id: String, force: Bool) async throws {
        deleteCallCount += 1
        lastDeletedID = id
        lastDeleteForce = force
        if let deleteError { throw deleteError }
    }

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

extension ContainerSummary {
    static func mock(
        id: String,
        image: String = "alpine:latest",
        status: ContainerRuntimeStatus,
        startedAt: Date? = nil,
        portSummary: String = "—"
    ) -> ContainerSummary {
        ContainerSummary(
            id: id,
            image: image,
            status: status,
            startedAt: startedAt,
            portSummary: portSummary
        )
    }
}
