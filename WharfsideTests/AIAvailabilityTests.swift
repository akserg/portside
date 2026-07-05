// WharfsideTests/AIAvailabilityTests.swift
// Issue 0.5 — every degraded state is testable without Apple Intelligence
// because the FoundationModels call sits behind AvailabilityProviding.

import Foundation
import Testing
@testable import Wharfside

// MARK: - Test double

struct StubProvider: AvailabilityProviding {
    let sequence: [AICapability]
    private let index = Counter()

    func currentCapability() -> AICapability {
        sequence[min(index.next(), sequence.count - 1)]
    }

    /// Tiny thread-safe counter so the stub can model state changes across refreshes.
    final class Counter: @unchecked Sendable {
        private var value = -1
        private let lock = NSLock()
        func next() -> Int { lock.withLock { value += 1; return value } }
    }
}

// MARK: - Tests

@MainActor
struct AIAvailabilityServiceTests {

    @Test func initialStateIsCheckingBeforeFirstRefresh() {
        let service = AIAvailabilityService(provider: StubProvider(sequence: [.full]))
        #expect(service.capability == .heuristicsOnly(.checking))
        #expect(!service.capability.isAIAvailable)
    }

    @Test func refreshAdoptsProviderState() {
        let service = AIAvailabilityService(provider: StubProvider(sequence: [.full]))
        service.refresh()
        #expect(service.capability == .full)
        #expect(service.capability.isAIAvailable)
    }

    @Test func modelDownloadingIsRememberedAcrossTransitionToFull() {
        let service = AIAvailabilityService(provider: StubProvider(sequence: [
            .heuristicsOnly(.modelNotReady),
            .full
        ]))
        service.refresh()
        #expect(service.sawModelDownloading)
        service.refresh()
        #expect(service.capability == .full)
        #expect(service.sawModelDownloading)   // sticky — UI may acknowledge activation
    }

    @Test func onlyNotEnabledIsUserActionable() {
        #expect(DegradedReason.appleIntelligenceNotEnabled.isUserActionable)
        #expect(!DegradedReason.deviceNotEligible.isUserActionable)
        #expect(!DegradedReason.modelNotReady.isUserActionable)
        #expect(!DegradedReason.checking.isUserActionable)
        #expect(!DegradedReason.other("x").isUserActionable)
    }

    @Test func everyReasonHasNonEmptyUserMessage() {
        let reasons: [DegradedReason] = [
            .deviceNotEligible, .appleIntelligenceNotEnabled,
            .modelNotReady, .checking, .other("detail")
        ]
        for reason in reasons {
            #expect(!reason.userMessage.isEmpty)
        }
    }
}
