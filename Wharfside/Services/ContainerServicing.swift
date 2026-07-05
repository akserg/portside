// Services/ContainerServicing.swift

import Foundation

protocol ContainerServicing: Sendable {
    func list() async throws -> [ContainerSummary]
    func get(id: String) async throws -> ContainerDetail
    func create(id: String, image: String, command: [String]) async throws
    func start(id: String) async throws
    func stop(id: String, timeout: TimeInterval) async throws
    func kill(id: String, signal: String) async throws
    func delete(id: String, force: Bool) async throws
    func stats(id: String) async throws -> ContainerStats
    func logStream(id: String, source: LogSource?) -> AsyncThrowingStream<LogChunk, Error>
    func exec(id: String, command: [String]) async throws -> ExecResult
}

protocol ImageServicing: Sendable {
    func list() async throws -> [ImageSummary]
    func pull(reference: String, onProgress: (@Sendable (PullProgress) -> Void)?) async throws -> ImageSummary
    func delete(reference: String) async throws
    func tag(source: String, target: String) async throws -> ImageSummary
}

protocol MachineServicing: Sendable {
    func list() async throws -> [MachineSummary]
    func inspect(id: String) async throws -> MachineDetail
    func stop(id: String) async throws
    func delete(id: String) async throws
}

protocol SystemServicing: Sendable {
    func health() async throws -> SystemHealth
    func defaultKernelInstalled() async -> Bool
}
