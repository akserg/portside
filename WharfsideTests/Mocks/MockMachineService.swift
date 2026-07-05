// WharfsideTests/Mocks/MockMachineService.swift

import Foundation
@testable import Wharfside

final class MockMachineService: MachineServicing, @unchecked Sendable {
    var machines: [MachineSummary] = []

    func list() async throws -> [MachineSummary] {
        machines
    }

    func inspect(id: String) async throws -> MachineDetail {
        MachineDetail(
            id: id,
            image: "alpine",
            status: .stopped,
            containerID: nil,
            ipAddress: nil,
            diskSizeBytes: nil,
            startedAt: nil,
            createdAt: nil,
            initialized: false
        )
    }

    func stop(id: String) async throws {}

    func delete(id: String) async throws {}
}
