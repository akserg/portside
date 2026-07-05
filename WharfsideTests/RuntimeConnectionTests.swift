// WharfsideTests/RuntimeConnectionTests.swift

import ContainerizationError
import Testing
@testable import Wharfside

@MainActor
struct RuntimeConnectionTests {
    @Test func retryPolicyAllowsInterruptRetryForReads() {
        let interrupted = ContainerizationError(
            .interrupted,
            message: "XPC connection error: Connection invalid"
        )
        #expect(ConnectionRetryPolicy.shouldRetry(
            retryOnInterrupt: true,
            error: interrupted,
            attempt: 1,
            maxAttempts: 2
        ))
    }

    @Test func retryPolicySkipsMutations() {
        let interrupted = ContainerizationError(
            .interrupted,
            message: "XPC connection error: Connection invalid"
        )
        #expect(!ConnectionRetryPolicy.shouldRetry(
            retryOnInterrupt: false,
            error: interrupted,
            attempt: 1,
            maxAttempts: 2
        ))
    }

    @Test func retryPolicyStopsAfterMaxAttempts() {
        let interrupted = ContainerizationError(
            .interrupted,
            message: "XPC connection error: Connection invalid"
        )
        #expect(!ConnectionRetryPolicy.shouldRetry(
            retryOnInterrupt: true,
            error: interrupted,
            attempt: 2,
            maxAttempts: 2
        ))
    }

    @Test func isInterruptedDetectsWrappedCause() {
        let wrapped = ContainerizationError(
            .internalError,
            message: "failed to list containers",
            cause: ContainerizationError(
                .interrupted,
                message: "XPC connection error: Connection invalid"
            )
        )
        #expect(ErrorMapper.isInterrupted(wrapped))
    }
}
