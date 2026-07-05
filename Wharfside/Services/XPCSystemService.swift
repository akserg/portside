// Services/XPCSystemService.swift

import ContainerAPIClient
import ContainerizationError
import Foundation

actor XPCSystemService: SystemServicing {
    func health() async throws -> SystemHealth {
        do {
            let health = try await ClientHealthCheck.ping()
            return RuntimeModelMapping.systemHealth(from: health)
        } catch {
            throw ErrorMapper.map(error)
        }
    }

    func defaultKernelInstalled() async -> Bool {
        do {
            _ = try await ClientKernel.getDefaultKernel(for: .current)
            return true
        } catch let error as ContainerizationError where error.isCode(.notFound) {
            return false
        } catch {
            return false
        }
    }
}
