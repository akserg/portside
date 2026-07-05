// Services/WharfsideError.swift

import ContainerizationError
import Foundation

enum WharfsideError: LocalizedError, Equatable {
    case serviceNotRunning
    case connectionFailed(String)
    case notFound(String)
    case invalidArgument(String)
    case invalidState(String)
    case invalidOperation(String)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .serviceNotRunning:
            "Container service is not running"
        case .connectionFailed(let message):
            "Connection failed: \(message)"
        case .notFound(let message):
            message
        case .invalidArgument(let message):
            message
        case .invalidState(let message):
            message
        case .invalidOperation(let message):
            "Invalid operation: \(message)"
        case .apiError(let message):
            message
        }
    }
}

enum ErrorMapper {
    nonisolated static func map(_ error: Error) -> WharfsideError {
        if let mapped = error as? WharfsideError {
            return mapped
        }

        if let root = error as? ContainerizationError {
            return mapContainerizationError(root)
        }

        if let nested = rootContainerizationError(from: error) {
            return mapContainerizationError(nested)
        }

        return .apiError(error.localizedDescription)
    }

    nonisolated static func isInterrupted(_ error: Error) -> Bool {
        if let root = rootContainerizationError(from: error) {
            return root.isCode(.interrupted) || containsInterruptedCause(in: root)
        }
        return false
    }

    nonisolated static func rootContainerizationError(from error: Error) -> ContainerizationError? {
        var current: Error? = error
        var lastContainerError: ContainerizationError?

        while let next = current {
            if let containerError = next as? ContainerizationError {
                lastContainerError = containerError
            }
            if let containerError = next as? ContainerizationError, containerError.cause == nil {
                return containerError
            }
            if let containerError = next as? ContainerizationError {
                current = containerError.cause
                continue
            }
            break
        }

        return lastContainerError
    }

    nonisolated static func mapContainerizationError(_ error: ContainerizationError) -> WharfsideError {
        guard let resolved = resolveSemanticCode(in: error) else {
            return .apiError(error.message)
        }

        if resolved == .interrupted {
            if error.message.contains("Connection invalid")
                || error.message.contains("Connection interrupted")
                || containsInterruptedCause(in: error) {
                return .serviceNotRunning
            }
            return .connectionFailed(error.message)
        }
        if resolved == .notFound {
            return .notFound(error.message)
        }
        if resolved == .invalidArgument {
            return .invalidArgument(error.message)
        }
        if resolved == .invalidState {
            return .invalidState(error.message)
        }

        return .apiError(error.message)
    }

    nonisolated private static func resolveSemanticCode(
        in error: ContainerizationError
    ) -> ContainerizationError.Code? {
        var current: Error? = error
        while let next = current {
            if let containerError = next as? ContainerizationError {
                if !containerError.isCode(.internalError) {
                    return containerError.code
                }
                current = containerError.cause
                continue
            }
            break
        }
        return nil
    }

    nonisolated private static func containsInterruptedCause(in error: ContainerizationError) -> Bool {
        var current: Error? = error.cause
        while let next = current {
            if let containerError = next as? ContainerizationError, containerError.isCode(.interrupted) {
                return true
            }
            if let containerError = next as? ContainerizationError {
                current = containerError.cause
                continue
            }
            break
        }
        return false
    }
}
