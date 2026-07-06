// WharfsideTests/Mocks/MockContainerService.swift

import Foundation
@testable import Wharfside

final class MockContainerService: ContainerServicing, @unchecked Sendable {
    var summaries: [ContainerSummary] = []
    var detailsByID: [String: ContainerDetail] = [:]
    var detail = ContainerDetail(
        id: "mock",
        image: "alpine",
        status: .stopped,
        command: ["/bin/sh"],
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        startedAt: nil,
        exitCode: nil,
        restartCount: 0,
        ports: [],
        mounts: [],
        environment: [],
        networks: []
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
    private(set) var getCallCount = 0
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0
    private(set) var killCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var lastGetID: String?
    private(set) var lastStartedID: String?
    private(set) var lastStoppedID: String?
    private(set) var lastKilledID: String?
    private(set) var lastDeletedID: String?
    private(set) var lastDeleteForce: Bool?

    var listError: Error?
    var getError: Error?
    var getErrorsByID: [String: Error] = [:]
    var startError: Error?
    var stopError: Error?
    var killError: Error?
    var deleteError: Error?
    var listDelay: Duration?
    var getDelay: Duration?

    var logStreamFactory: (@Sendable (String, LogSource?) -> AsyncThrowingStream<LogChunk, Error>)?

    private(set) var logStreamCallCount = 0
    private(set) var lastLogStreamID: String?
    private(set) var lastLogStreamSource: LogSource?

    func list() async throws -> [ContainerSummary] {
        listCallCount += 1
        if let listDelay {
            try await Task.sleep(for: listDelay)
        }
        if let listError { throw listError }
        return summaries
    }

    func get(id: String) async throws -> ContainerDetail {
        getCallCount += 1
        lastGetID = id
        if let getDelay {
            try await Task.sleep(for: getDelay)
        }
        if let error = getErrorsByID[id] ?? getError {
            throw error
        }
        if let detail = detailsByID[id] {
            return detail
        }
        return detail
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
        logStreamCallCount += 1
        lastLogStreamID = id
        lastLogStreamSource = source
        if let logStreamFactory {
            return logStreamFactory(id, source)
        }
        return AsyncThrowingStream { continuation in
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

extension ContainerDetail {
    static func mock(
        id: String,
        image: String = "alpine:latest",
        status: ContainerRuntimeStatus = .running,
        createdAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        startedAt: Date? = Date(timeIntervalSince1970: 1_700_010_000),
        exitCode: Int32? = nil,
        restartCount: Int = 0,
        ports: [ContainerPortBinding] = [
            ContainerPortBinding(hostAddress: "0.0.0.0", hostPort: 8080, containerPort: 80, proto: "tcp")
        ],
        mounts: [ContainerMount] = [
            ContainerMount(source: "/host/data", destination: "/data", type: "virtiofs", readOnly: false)
        ],
        environment: [ContainerEnvironmentVariable] = [
            ContainerEnvironmentVariable(key: "SECRET_TOKEN", value: "super-secret")
        ],
        networks: [ContainerNetworkAttachment] = [
            ContainerNetworkAttachment(
                network: "default",
                hostname: "app",
                ipv4Address: "192.168.64.2/24",
                ipv4Gateway: "192.168.64.1",
                ipv6Address: nil
            )
        ]
    ) -> ContainerDetail {
        ContainerDetail(
            id: id,
            image: image,
            status: status,
            command: ["/bin/sh"],
            createdAt: createdAt,
            startedAt: startedAt,
            exitCode: exitCode,
            restartCount: restartCount,
            ports: ports,
            mounts: mounts,
            environment: environment,
            networks: networks
        )
    }
}
