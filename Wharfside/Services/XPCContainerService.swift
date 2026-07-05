// Services/XPCContainerService.swift

import ContainerAPIClient
import ContainerResource
import Containerization
import Foundation

/// XPC-backed container operations via `ContainerClient`.
///
/// Exec cancellation must use container-level `kill(id:signal:)` — `ClientProcess.kill` is broken
/// on apple/container 1.0 (capability map row 11).
actor XPCContainerService: ContainerServicing {
    private let connection = RuntimeConnection()

    func list() async throws -> [ContainerSummary] {
        try await connection.withContainerClient(retryOnInterrupt: true) { client in
            let snapshots = try await client.list(filters: .all)
            return snapshots.map(RuntimeModelMapping.containerSummary(from:))
        }
    }

    func get(id: String) async throws -> ContainerDetail {
        try await connection.withContainerClient(retryOnInterrupt: true) { client in
            let snapshot = try await client.get(id: id)
            return RuntimeModelMapping.containerDetail(from: snapshot)
        }
    }

    func create(id: String, image: String, command: [String]) async throws {
        let systemConfig = try await ContainerCreateSupport.loadSystemConfig()
        try await ContainerCreateSupport.prepareInitImage(systemConfig: systemConfig)
        let imageObject = try await ContainerCreateSupport.prepareImage(
            reference: image,
            systemConfig: systemConfig
        )
        let (configuration, kernel) = try await ContainerCreateSupport.makeConfiguration(
            id: id,
            image: imageObject,
            command: command,
            systemConfig: systemConfig
        )

        try await connection.withContainerClient(retryOnInterrupt: false) { client in
            try await client.create(configuration: configuration, options: .default, kernel: kernel)
        }
    }

    func start(id: String) async throws {
        try await connection.withContainerClient(retryOnInterrupt: false) { client in
            let nullOut = try FileHandle(forWritingTo: URL(fileURLWithPath: "/dev/null"))
            let process = try await client.bootstrap(id: id, stdio: [nil, nullOut, nullOut])
            try await process.start()
        }
    }

    func stop(id: String, timeout: TimeInterval) async throws {
        let options = ContainerStopOptions(timeoutInSeconds: Int32(timeout), signal: nil)
        try await connection.withContainerClient(retryOnInterrupt: false) { client in
            try await client.stop(id: id, opts: options)
        }
    }

    func kill(id: String, signal: String) async throws {
        try await connection.withContainerClient(retryOnInterrupt: false) { client in
            try await client.kill(id: id, signal: signal)
        }
    }

    func delete(id: String, force: Bool) async throws {
        try await connection.withContainerClient(retryOnInterrupt: false) { client in
            try await client.delete(id: id, force: force)
        }
    }

    func stats(id: String) async throws -> ContainerStats {
        try await connection.withContainerClient(retryOnInterrupt: true) { client in
            let stats = try await client.stats(id: id)
            return RuntimeModelMapping.containerStats(from: stats)
        }
    }

    nonisolated func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error> {
        AsyncThrowingStream { continuation in
            let resources = LogStreamResources()

            let task = Task {
                do {
                    try await self.runLogStream(
                        id: id,
                        source: source,
                        resources: resources,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
                resources.closeAll()
            }

            continuation.onTermination = { _ in
                task.cancel()
                resources.closeAll()
            }
        }
    }

    func exec(id: String, command: [String]) async throws -> ExecResult {
        guard let executable = command.first else {
            throw WharfsideError.invalidArgument("exec command must not be empty")
        }

        return try await connection.withContainerClient(retryOnInterrupt: false) { client in
            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            let processID = "wharfside-exec-\(UUID().uuidString)"
            let configuration = ProcessConfiguration(
                executable: executable,
                arguments: Array(command.dropFirst()),
                environment: [],
                workingDirectory: "/",
                terminal: false
            )

            let process = try await client.createProcess(
                containerId: id,
                processId: processID,
                configuration: configuration,
                stdio: [nil, stdoutPipe.fileHandleForWriting, stderrPipe.fileHandleForWriting]
            )
            try await process.start()
            let exitCode = try await process.wait()

            stdoutPipe.fileHandleForWriting.closeFile()
            stderrPipe.fileHandleForWriting.closeFile()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return ExecResult(
                exitCode: exitCode,
                stdout: String(data: stdoutData, encoding: .utf8) ?? "",
                stderr: String(data: stderrData, encoding: .utf8) ?? ""
            )
        }
    }

    private func runLogStream(
        id: String,
        source: LogSource?,
        resources: LogStreamResources,
        continuation: AsyncThrowingStream<LogChunk, Error>.Continuation
    ) async throws {
        let handles = try await connection.withContainerClient(retryOnInterrupt: true) { client in
            try await client.logs(id: id)
        }
        resources.store(handles)

        var labeledHandles: [(LogSource, FileHandle)] = []
        if source == nil || source == .stdio, handles.indices.contains(0) {
            labeledHandles.append((.stdio, handles[0]))
        }
        if source == nil || source == .boot, handles.indices.contains(1) {
            labeledHandles.append((.boot, handles[1]))
        }

        guard !labeledHandles.isEmpty else {
            throw WharfsideError.apiError("No log handles returned for container \(id)")
        }

        while !Task.isCancelled {
            for (logSource, handle) in labeledHandles {
                let data = handle.availableData
                if !data.isEmpty {
                    continuation.yield(LogChunk(source: logSource, data: data))
                }
            }
            try await Task.sleep(for: .milliseconds(250))
        }
    }
}

/// Thread-safe holder so `onTermination` can close log `FileHandle`s when the stream is cancelled.
private final class LogStreamResources: @unchecked Sendable {
    private let lock = NSLock()
    nonisolated(unsafe) private var handles: [FileHandle] = []

    nonisolated init() {}

    nonisolated func store(_ handles: [FileHandle]) {
        lock.lock()
        defer { lock.unlock() }
        self.handles = handles
    }

    nonisolated func closeAll() {
        lock.lock()
        defer { lock.unlock() }
        for handle in handles {
            try? handle.close()
        }
        handles = []
    }
}
