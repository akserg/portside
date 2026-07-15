// WharfsideTests/DaemonVersionPolicyTests.swift

import Testing
@testable import Wharfside

@Suite
struct DaemonVersionPolicyTests {
    @Test func preOnePointZeroWhenMajorIsZero() {
        #expect(DaemonVersionPolicy.isPreOnePointZero(apiServerVersion: "0.33.3"))
    }

    @Test func notPreOnePointZeroAtOneOh() {
        #expect(!DaemonVersionPolicy.isPreOnePointZero(apiServerVersion: "1.0.0"))
    }

    @Test func unknownVersionDoesNotTriggerBanner() {
        #expect(!DaemonVersionPolicy.isPreOnePointZero(apiServerVersion: nil))
        #expect(!DaemonVersionPolicy.isPreOnePointZero(apiServerVersion: ""))
    }
}
