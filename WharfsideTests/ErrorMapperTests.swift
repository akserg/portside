// WharfsideTests/ErrorMapperTests.swift

import ContainerizationError
import Testing
@testable import Wharfside

@MainActor
struct ErrorMapperTests {
    @Test func daemonDownPing() {
        let error = ContainerizationError(
            .interrupted,
            message: "XPC connection error: Connection invalid"
        )
        #expect(ErrorMapper.map(error) == .serviceNotRunning)
    }

    @Test func daemonDownList() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to list containers",
            cause: ContainerizationError(
                .interrupted,
                message: "XPC connection error: Connection invalid"
            )
        )
        #expect(ErrorMapper.map(error) == .serviceNotRunning)
    }

    @Test func daemonDownGet() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to list containers",
            cause: ContainerizationError(
                .interrupted,
                message: "XPC connection error: Connection invalid"
            )
        )
        #expect(ErrorMapper.map(error) == .serviceNotRunning)
    }

    @Test func notFoundContainerGet() {
        let error = ContainerizationError(
            .notFound,
            message: "get failed: container spike-nonexistent not found"
        )
        #expect(ErrorMapper.map(error) == .notFound("get failed: container spike-nonexistent not found"))
    }

    @Test func notFoundContainerLogs() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to get logs for container spike-nonexistent",
            cause: ContainerizationError(
                .internalError,
                message: "failed to open container logs: notFound: \"container with ID spike-nonexistent not found\"",
                cause: ContainerizationError(
                    .notFound,
                    message: "container with ID spike-nonexistent not found"
                )
            )
        )
        #expect(
            ErrorMapper.map(error)
                == .notFound("failed to get logs for container spike-nonexistent")
        )
    }

    @Test func notFoundMachineInspect() {
        let error = ContainerizationError(
            .internalError,
            message: "failed to inspect container machine",
            cause: ContainerizationError(
                .notFound,
                message: "container machine with ID spike-nonexistent-machine not found"
            )
        )
        #expect(
            ErrorMapper.map(error)
                == .notFound("failed to inspect container machine")
        )
    }

    @Test func notFoundVolumeInspect() {
        let error = ContainerizationError(
            .invalidArgument,
            message: "volume 'spike-nonexistent-volume' not found"
        )
        #expect(
            ErrorMapper.map(error)
                == .invalidArgument("volume 'spike-nonexistent-volume' not found")
        )
    }
}
