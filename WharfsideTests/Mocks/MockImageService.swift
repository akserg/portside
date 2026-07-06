// WharfsideTests/Mocks/MockImageService.swift

import Foundation
@testable import Wharfside

final class MockImageService: ImageServicing, @unchecked Sendable {
    var images: [ImageSummary] = []
    var listDelay: Duration = .zero
    var pullDelay: Duration = .zero
    var listError: WharfsideError?
    var deleteError: Error?
    var deleteShouldFailNotFound = false
    var pullError: Error?
    var pullHandler: (@Sendable (String, (@Sendable (PullProgress) -> Void)?) async throws -> ImageSummary)?

    private(set) var listCallCount = 0
    private(set) var deleteCallCount = 0
    private(set) var pullCallCount = 0
    private(set) var activePullReferences: Set<String> = []
    private(set) var pullReferences: [String] = []

    func list() async throws -> [ImageSummary] {
        listCallCount += 1
        if listDelay > .zero {
            try await Task.sleep(for: listDelay)
        }
        if let listError {
            throw listError
        }
        return images
    }

    func pull(reference: String, onProgress: (@Sendable (PullProgress) -> Void)?) async throws -> ImageSummary {
        pullCallCount += 1
        pullReferences.append(reference)
        activePullReferences.insert(reference)
        defer { activePullReferences.remove(reference) }

        if pullDelay > .zero {
            try await Task.sleep(for: pullDelay)
        }

        if let pullHandler {
            return try await pullHandler(reference, onProgress)
        }

        onProgress?(PullProgress(description: "Downloading", completedUnits: 1, totalUnits: 2))
        onProgress?(PullProgress(description: "Complete", completedUnits: 2, totalUnits: 2))

        if let pullError {
            throw pullError
        }

        return ImageSummary(reference: reference, digest: "sha256:mock")
    }

    func delete(reference: String) async throws {
        deleteCallCount += 1
        if deleteShouldFailNotFound {
            throw WharfsideError.notFound("Image not found: \(reference)")
        }
        if let deleteError {
            throw deleteError
        }
    }

    func tag(source: String, target: String) async throws -> ImageSummary {
        ImageSummary(reference: target, digest: "sha256:mock")
    }
}

extension ImageSummary {
    static func mock(
        reference: String,
        digest: String = "sha256:abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890",
        sizeBytes: Int64? = 4_194_304,
        createdAt: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> ImageSummary {
        ImageSummary(reference: reference, digest: digest, sizeBytes: sizeBytes, createdAt: createdAt)
    }
}
