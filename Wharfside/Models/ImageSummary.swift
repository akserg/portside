// Models/ImageSummary.swift

import Foundation

struct ImageSummary: Sendable, Hashable, Identifiable {
    var id: String { reference }
    let reference: String
    let digest: String
    let sizeBytes: Int64?
    let createdAt: Date?

    nonisolated init(reference: String, digest: String, sizeBytes: Int64? = nil, createdAt: Date? = nil) {
        self.reference = reference
        self.digest = digest
        self.sizeBytes = sizeBytes
        self.createdAt = createdAt
    }
}
