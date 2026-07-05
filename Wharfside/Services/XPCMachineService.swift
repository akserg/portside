// Services/XPCMachineService.swift

import Foundation
import MachineAPIClient

actor XPCMachineService: MachineServicing {
    private let connection = RuntimeConnection()

    func list() async throws -> [MachineSummary] {
        try await connection.withMachineClient(retryOnInterrupt: true) { client in
            let machines = try await client.list()
            return machines.map(RuntimeModelMapping.machineSummary(from:))
        }
    }

    func inspect(id: String) async throws -> MachineDetail {
        try await connection.withMachineClient(retryOnInterrupt: true) { client in
            let snapshot = try await client.inspect(id: id)
            return RuntimeModelMapping.machineDetail(from: snapshot)
        }
    }

    func stop(id: String) async throws {
        try await connection.withMachineClient(retryOnInterrupt: false) { client in
            try await client.stop(id: id)
        }
    }

    func delete(id: String) async throws {
        try await connection.withMachineClient(retryOnInterrupt: false) { client in
            try await client.delete(id: id)
        }
    }
}
