// WharfsideTests/Mocks/MockSystemService.swift

import Foundation
@testable import Wharfside

final class MockSystemService: SystemServicing, @unchecked Sendable {
    var healthResult: Result<SystemHealth, Error> = .success(
        SystemHealth(
            apiServerVersion: "1.0.0",
            apiServerCommit: "mock",
            apiServerBuild: "release",
            apiServerAppName: "container",
            appRoot: URL(fileURLWithPath: "/tmp"),
            installRoot: URL(fileURLWithPath: "/tmp"),
            logRootPath: nil
        )
    )
    var defaultKernelInstalledResult = true

    private(set) var healthCallCount = 0

    func health() async throws -> SystemHealth {
        healthCallCount += 1
        return try healthResult.get()
    }

    func defaultKernelInstalled() async -> Bool {
        defaultKernelInstalledResult
    }
}
